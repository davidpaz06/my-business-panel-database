# Flujo: Prestaciones sociales y liquidacion (LOTTT Venezuela)

Documenta el modelo de datos que soporta el modulo de RRHH tras la migracion normativa de Costa Rica a Venezuela. Cubre las tablas creadas por las migraciones `hr/006` a `hr/018`, sus invariantes y las consultas canonicas.

Referencia legal: **Ley Organica del Trabajo, los Trabajadores y las Trabajadoras**, Gaceta Oficial N 6.076 Extraordinario, 07-05-2012.

---

## Por que cambio el modelo

En Costa Rica el auxilio de cesantia se calculaba **una sola vez, al final** de la relacion, con el salario de ese momento. No habia estado que persistir durante la vigencia del contrato.

El Art. 142 venezolano funciona al reves: la garantia de prestaciones se **deposita trimestralmente** y devenga intereses mientras esta depositada. El sistema debe llevar un saldo vivo. De ahi que aparezcan tablas que antes no tenian equivalente.

Ademas, el Art. 142 obliga a un **doble calculo con seleccion del monto mayor**, y el Art. 51 fija prescripcion de 10 anios para prestaciones. Consecuencia de diseno: no basta con guardar el monto pagado, hay que guardar **por que** ese monto era el correcto.

---

## Mapa de tablas

```
hr_schema
├── payroll_parameters          Parametros con vigencia temporal por tenant
├── salary_history              Salario mensual con vigencia (Art. 122)
├── overtime_record             Horas con recargo por evento (Arts. 117-120, 178)
├── severance_deposit           Garantia trimestral (Art. 142.a)
├── severance_interest          Intereses mensuales (Art. 143)
├── severance_advance           Anticipos hasta 75% (Art. 144)
├── vacation_period             Vacaciones y bono por anio (Arts. 190, 192)
├── profit_sharing_period       Ejercicio anual de utilidades (Art. 131)
├── profit_sharing_detail       Cuota por trabajador (Art. 136)
├── settlement                  Liquidacion final (Art. 142.d)
├── settlement_item             Desglose auditable (Art. 106)
├── employee_beneficiary        Herederos (Art. 145)
└── employee_deduction          Descuentos con topes (Arts. 152, 154)
```

Columnas agregadas a tablas existentes:

| Tabla | Columnas | Motivo |
| --- | --- | --- |
| `employee` | `hire_date`, `termination_date`, `termination_type`, `termination_reason` | Antiguedad (Art. 142) e indemnizacion (Art. 92) |
| `contract` | `journey_type`, `weekly_hours`; `end_date` pasa a NULLABLE | Jornada (Art. 173); contrato indefinido es la regla general |
| `holiday` | `tenant_id`, `holiday_year`, `is_recurring`, `source` | Feriados moviles y declarados (Art. 184) |
| `payroll_concept` | `article`, `salary_basis` | Trazabilidad legal y base de calculo |
| `payroll_concept_template` | `article`, `salary_basis`, `is_active` | Idem, mas conceptos definidos pero no liberados |

---

## Invariantes que el modelo protege

### 1. Cada trimestre congela su propia base salarial

`severance_deposit.integral_daily_salary` guarda el salario integral **vigente en ese trimestre**, no el actual. Un aumento posterior no lo modifica.

Sin esto, tras un aumento se perderia la base historica y la Via 1 del Art. 142 no seria reconstruible.

```sql
-- Verificacion: los trimestres previos a un aumento deben mostrar
-- una base distinta a los posteriores.
SELECT quarter_start, integral_daily_salary, amount
FROM hr_schema.severance_deposit
WHERE employee_id = $1
ORDER BY quarter_start;
```

Si todas las filas muestran el mismo `integral_daily_salary`, el congelado esta roto.

### 2. El incumplimiento del deposito es un dato de negocio

`severance_deposit.deposit_made = FALSE` no es un flag operativo: **determina la tasa de interes aplicable**. El Art. 143 penaliza al patrono que no deposito haciendo que la garantia devengue la tasa **activa** del BCV, la mas alta.

```sql
-- Trimestres que disparan penalizacion
SELECT quarter_start, quarter_end, amount
FROM hr_schema.severance_deposit
WHERE employee_id = $1 AND deposit_made = FALSE;
```

### 3. Las tasas aplicadas se persisten, no se recalculan

`severance_interest.applied_rate` y `settlement.mora_rate` guardan la tasa **efectivamente usada**. La tasa del BCV cambia; un recalculo con la tasa de hoy daria un resultado distinto al que se pago.

Mismo criterio en `overtime_record.rate_factor`: se guarda el factor del momento (1.50 con permiso de Inspectoria, 2.00 sin el, Art. 182).

### 4. Ambas vias del Art. 142 quedan registradas

`settlement.via1_amount`, `via2_amount` y `selected_via` se persisten siempre, no solo el ganador.

Ante un reclamo laboral hay que poder demostrar por que se pago ese monto. Con prescripcion de 10 anios (Art. 51), recalcular anios despues con parametros distintos no reconstruye la decision original.

### 5. El total de la liquidacion es la suma de sus renglones

`settlement_item` lleva un renglon por concepto, con su base, dias, articulo y formula legible (Art. 106). Los conceptos que restan (anticipos del Art. 144, descuentos del Art. 154) van con `amount` **negativo**, no restados por fuera del desglose.

```sql
-- El desglose debe cuadrar con la cabecera
SELECT s.subtotal, SUM(si.amount) AS suma_renglones
FROM hr_schema.settlement s
JOIN hr_schema.settlement_item si USING (settlement_id)
WHERE s.settlement_id = $1
GROUP BY s.subtotal;
```

### 6. La base salarial es explicita, nunca implicita

`payroll_concept.salary_basis` y `settlement_item.salary_basis` obligan a declarar si el concepto usa salario **normal** (Art. 104) o **integral** (Art. 122).

| Base | Se usa para |
| --- | --- |
| `normal` | Recargos, feriados, vacaciones, bono vacacional, utilidades |
| `integral` | Prestaciones e indemnizaciones |

Usar la base equivocada es el error de calculo mas frecuente. Al ser un dato del concepto, deja de depender de que cada servicio lo recuerde.

---

## Consultas canonicas

### Resolver un parametro a una fecha

```sql
SELECT param_value FROM hr_schema.payroll_parameters
WHERE tenant_id = $1 AND param_key = $2
  AND valid_from <= $3 AND (valid_to IS NULL OR valid_to >= $3)
ORDER BY valid_from DESC LIMIT 1;
```

Nunca leer "el ultimo registro" sin filtrar por vigencia: un recalculo historico debe devolver el valor que regia entonces.

### Resolver el salario a una fecha

```sql
SELECT monthly_salary FROM hr_schema.salary_history
WHERE employee_id = $1
  AND valid_from <= $2 AND (valid_to IS NULL OR valid_to >= $2)
ORDER BY valid_from DESC LIMIT 1;
```

### Acumulado anual de horas extra (tope Art. 178)

```sql
SELECT COALESCE(SUM(hours), 0) FROM hr_schema.overtime_record
WHERE employee_id = $1 AND kind = 'extra'
  AND work_date >= date_trunc('year', $2::date)
  AND work_date <  date_trunc('year', $2::date) + INTERVAL '1 year';
```

### Saldo de la garantia (base del tope del Art. 144)

```sql
saldo = SUM(severance_deposit.amount   WHERE deposit_made)
      + SUM(severance_interest.amount  WHERE capitalized)
      - SUM(severance_advance.approved_amount WHERE status = 'aprobado')

max_anticipo = saldo * 0.75
```

---

## Validaciones que NO estan en el schema

Requieren agregacion o dependen del salario vigente, por lo que viven en la capa de aplicacion:

| Regla | Articulo | Donde |
| --- | --- | --- |
| Topes de horas extra (10/dia, 10/sem, 100/anio) | 178 | `journey` |
| Maximo 3 feriados declarados por anio | 184.d | `journey` |
| Anticipo hasta 75% del saldo | 144 | `severance` |
| Descuento hasta 1/3 del periodo (acumulado) | 154 | `deductions` |
| Compensacion hasta 50% del credito a favor | 154 | `deductions` |
| Parametro no puede bajar del piso legal | 18.2, 434 | `parameters` |

---

## Estado y pendientes

**Hecho:** migraciones `hr/006` a `hr/018`, seeds de feriados VE, conceptos LOTTT y parametros con pisos legales, `hr_schema.sql` actualizado como fuente de verdad, `provision_tenant_payroll_concepts()` y `create_new_employee()` ajustadas.

**Eliminado:** `generate_monthly_ccss()` era especifica de la Caja Costarricense de Seguro Social y ademas estaba rota (referenciaba `ccss_employee_deduction`, `ccss_tenant_deduction` y `paysheet.payment_day`, ninguna existente en el esquema).

**Pendiente:**

1. **Retenciones mensuales venezolanas** (IVSS, INCES, FAOV, Paro Forzoso, ISLR). La especificacion de origen no las cubre. Los conceptos estan sembrados **inactivos** con `base_value = 0` para dejar el hueco trazado. Sin spec propia, la nomina mensual produce un neto sin deducciones legales.
2. **Carga de `tasa_activa_bcv`** con vigencia periodica. Sin ella fallan los calculos de intereses y mora.
3. **`liquid_benefits`** para utilidades: proviene del cierre contable del contexto `finances`.
4. **Feriados de fecha movil**: carnaval y Semana Santa dependen de la fecha de Pascua y requieren carga anual.
5. **Backend**: ver `my-business-panel-backend/src/contexts/hr/ROADMAP-LOTTT.md`.

## Aviso

La interpretacion recogida aqui proviene de `MBP_Nomina_LOTTT_Venezuela.md`, que advierte explicitamente no constituir asesoria legal. Antes de liberar los calculos a produccion conviene validacion de un especialista en derecho laboral venezolano.
