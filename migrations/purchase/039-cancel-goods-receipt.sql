-- Migracion 039: cancelar una recepcion de mercancia iniciada por error.
--
-- Contexto: el flujo start/update/confirm goods_receipt (migracion 037) no
-- tenia salida para abortar una recepcion que se inicio por error o que el
-- usuario quiere reintentar desde cero -- la unica opcion era "Guardar
-- correccion" (guardar items a medias) seguido de "Confirmar", sin forma de
-- cancelar. cancel_goods_receipt() borra el goods_receipt PENDING (cascada
-- elimina sus goods_receipt_item) para que start_goods_receipt() pueda
-- volver a crear uno limpio. Solo permite cancelar mientras sigue PENDING --
-- una vez CONFIRMED ya aplico inventario y corrio three-way matching, no es
-- reversible por aqui.

SET SEARCH_PATH = purchase_schema;

CREATE OR REPLACE FUNCTION cancel_goods_receipt(p_goods_receipt_id uuid) RETURNS VOID AS $$
DECLARE
    v_status VARCHAR(10);
BEGIN
    SELECT status INTO v_status
    FROM purchase_schema.goods_receipt
    WHERE goods_receipt_id = p_goods_receipt_id;

    IF v_status IS NULL THEN
        RAISE EXCEPTION 'goods_receipt % not found', p_goods_receipt_id;
    END IF;

    IF v_status <> 'PENDING' THEN
        RAISE EXCEPTION 'Solo se puede cancelar una recepcion mientras esta PENDING';
    END IF;

    DELETE FROM purchase_schema.goods_receipt WHERE goods_receipt_id = p_goods_receipt_id;
END;
$$ LANGUAGE plpgsql;

-- Rollback (comentado, documentacion -- no se ejecuta automaticamente):
-- DROP FUNCTION IF EXISTS purchase_schema.cancel_goods_receipt(uuid);
