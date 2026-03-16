SET SEARCH_PATH TO accounting_schema;

-- ============================================================
-- validate_journal_balance
-- Validates that a journal entry's debit and credit totals match.
-- Returns TRUE if balanced, raises exception if not.
-- ============================================================
CREATE OR REPLACE FUNCTION validate_journal_balance(_entry_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    _total_debit NUMERIC(14,4);
    _total_credit NUMERIC(14,4);
    _line_count INT;
BEGIN
    SELECT count(*),
           coalesce(sum(debit_amount), 0),
           coalesce(sum(credit_amount), 0)
    INTO _line_count, _total_debit, _total_credit
    FROM accounting_schema.journal_entry_line
    WHERE entry_id = _entry_id;

    IF _line_count = 0 THEN
        RAISE EXCEPTION 'Journal entry % has no lines', _entry_id;
    END IF;

    IF _line_count < 2 THEN
        RAISE EXCEPTION 'Journal entry % must have at least 2 lines (debit and credit)', _entry_id;
    END IF;

    IF _total_debit != _total_credit THEN
        RAISE EXCEPTION 'Journal entry % is unbalanced: debits=% credits=%',
            _entry_id, _total_debit, _total_credit;
    END IF;

    -- Update denormalized totals on the journal entry
    UPDATE accounting_schema.journal_entry
    SET total_debit = _total_debit,
        total_credit = _total_credit,
        updated_at = CURRENT_TIMESTAMP
    WHERE entry_id = _entry_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- confirm_journal_entry
-- Validates balance and transitions entry from Borrador → Confirmado
-- ============================================================
CREATE OR REPLACE FUNCTION confirm_journal_entry(_entry_id UUID)
RETURNS BOOLEAN AS $$
DECLARE
    _current_status INT;
    _status_borrador INT;
    _status_confirmado INT;
BEGIN
    SELECT status_id INTO _status_borrador
    FROM accounting_schema.journal_entry_status
    WHERE status_name = 'Borrador';

    SELECT status_id INTO _status_confirmado
    FROM accounting_schema.journal_entry_status
    WHERE status_name = 'Confirmado';

    SELECT status_id INTO _current_status
    FROM accounting_schema.journal_entry
    WHERE entry_id = _entry_id;

    IF _current_status IS NULL THEN
        RAISE EXCEPTION 'Journal entry % not found', _entry_id;
    END IF;

    IF _current_status != _status_borrador THEN
        RAISE EXCEPTION 'Journal entry % is not in Borrador status (current status_id=%)',
            _entry_id, _current_status;
    END IF;

    -- Validate balance before confirming
    PERFORM accounting_schema.validate_journal_balance(_entry_id);

    UPDATE accounting_schema.journal_entry
    SET status_id = _status_confirmado,
        updated_at = CURRENT_TIMESTAMP
    WHERE entry_id = _entry_id;

    RETURN TRUE;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- void_journal_entry
-- Transitions entry from Confirmado → Anulado.
-- Creates a reversal entry automatically.
-- ============================================================
CREATE OR REPLACE FUNCTION void_journal_entry(_entry_id UUID, _voided_by UUID DEFAULT NULL)
RETURNS UUID AS $$
DECLARE
    _current_status INT;
    _status_confirmado INT;
    _status_anulado INT;
    _entry RECORD;
    _reversal_id UUID;
    _source_type_adj INT;
BEGIN
    SELECT status_id INTO _status_confirmado
    FROM accounting_schema.journal_entry_status
    WHERE status_name = 'Confirmado';

    SELECT status_id INTO _status_anulado
    FROM accounting_schema.journal_entry_status
    WHERE status_name = 'Anulado';

    SELECT * INTO _entry
    FROM accounting_schema.journal_entry
    WHERE entry_id = _entry_id;

    IF _entry IS NULL THEN
        RAISE EXCEPTION 'Journal entry % not found', _entry_id;
    END IF;

    IF _entry.status_id != _status_confirmado THEN
        RAISE EXCEPTION 'Only confirmed entries can be voided (entry % has status_id=%)',
            _entry_id, _entry.status_id;
    END IF;

    -- Get ADJUSTMENT source type for the reversal
    SELECT source_type_id INTO _source_type_adj
    FROM accounting_schema.source_type
    WHERE source_name = 'ADJUSTMENT';

    -- Mark original as voided
    UPDATE accounting_schema.journal_entry
    SET status_id = _status_anulado,
        updated_at = CURRENT_TIMESTAMP
    WHERE entry_id = _entry_id;

    -- Create reversal entry (swap debits and credits)
    INSERT INTO accounting_schema.journal_entry(
        tenant_id, source_type_id, source_id, entry_date,
        description, status_id, total_debit, total_credit, created_by
    ) VALUES (
        _entry.tenant_id, _source_type_adj, _entry_id, CURRENT_DATE,
        'Reversión de asiento ' || _entry.entry_number,
        _status_confirmado, _entry.total_debit, _entry.total_credit, _voided_by
    ) RETURNING entry_id INTO _reversal_id;

    -- Copy lines with swapped debit/credit
    INSERT INTO accounting_schema.journal_entry_line(
        entry_id, account_id, cost_center_id, debit_amount, credit_amount, description
    )
    SELECT _reversal_id, account_id, cost_center_id,
           credit_amount AS debit_amount,
           debit_amount AS credit_amount,
           'Reversión: ' || coalesce(description, '')
    FROM accounting_schema.journal_entry_line
    WHERE entry_id = _entry_id;

    RETURN _reversal_id;
END;
$$ LANGUAGE plpgsql;


-- ============================================================
-- provision_tenant_accounts
-- Copies the chart of accounts template to a specific tenant.
-- Called during tenant onboarding.
-- ============================================================
CREATE OR REPLACE FUNCTION provision_tenant_accounts(_tenant_id UUID)
RETURNS INT AS $$
DECLARE
    _template RECORD;
    _parent_id UUID;
    _inserted INT := 0;
    _account_map JSONB := '{}';
BEGIN
    -- Check tenant exists
    IF NOT EXISTS (SELECT 1 FROM general_schema.tenant WHERE tenant_id = _tenant_id) THEN
        RAISE EXCEPTION 'Tenant % not found', _tenant_id;
    END IF;

    -- Check if tenant already has accounts
    IF EXISTS (SELECT 1 FROM accounting_schema.chart_of_accounts WHERE tenant_id = _tenant_id LIMIT 1) THEN
        RAISE NOTICE 'Tenant % already has chart of accounts provisioned', _tenant_id;
        RETURN 0;
    END IF;

    -- Insert accounts in order (parents first) using the template
    FOR _template IN
        SELECT * FROM accounting_schema.chart_of_accounts_template
        ORDER BY account_code
    LOOP
        -- Resolve parent
        _parent_id := NULL;
        IF _template.parent_code IS NOT NULL THEN
            _parent_id := (_account_map ->> _template.parent_code)::UUID;
        END IF;

        INSERT INTO accounting_schema.chart_of_accounts(
            tenant_id, account_code, account_name, account_type_id,
            parent_account_id, is_active, is_system, allows_transactions
        ) VALUES (
            _tenant_id, _template.account_code, _template.account_name, _template.account_type_id,
            _parent_id, TRUE, TRUE, _template.allows_transactions
        ) RETURNING account_id INTO _parent_id;

        -- Store in map for child resolution
        _account_map := _account_map || jsonb_build_object(_template.account_code, _parent_id::TEXT);
        _inserted := _inserted + 1;
    END LOOP;

    RAISE NOTICE 'Provisioned % accounts for tenant %', _inserted, _tenant_id;
    RETURN _inserted;
END;
$$ LANGUAGE plpgsql;
