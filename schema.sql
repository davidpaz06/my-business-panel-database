--
-- PostgreSQL database dump
--

\restrict RIQTKbTf60aFF66laZnokAtfcUjOBL8VxchYiWzopiO4vj0kge4655Dfe02pvfc

-- Dumped from database version 17.7 (Debian 17.7-3.pgdg13+1)
-- Dumped by pg_dump version 17.7 (Debian 17.7-3.pgdg13+1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: core; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA core;


--
-- Name: inventory_module; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA inventory_module;


--
-- Name: pos_module; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA pos_module;


--
-- Name: supplies_module; Type: SCHEMA; Schema: -; Owner: -
--

CREATE SCHEMA supplies_module;


--
-- Name: discount_result; Type: TYPE; Schema: pos_module; Owner: -
--

CREATE TYPE pos_module.discount_result AS (
	discount_amount numeric(10,2),
	discount_percentage numeric(5,2),
	rule_description text,
	success boolean
);


--
-- Name: count_warehouse_inventory_products(); Type: FUNCTION; Schema: inventory_module; Owner: -
--

CREATE FUNCTION inventory_module.count_warehouse_inventory_products() RETURNS TABLE(warehouse_id uuid, product_name character varying, product_count bigint)
    LANGUAGE plpgsql
    AS $$
BEGIN
    RETURN QUERY
    SELECT w.warehouse_id, p.product_name AS product_name, COUNT(i.product_id) AS product_count
    FROM inventory_module.warehouse w
    LEFT JOIN inventory_module.inventory i ON w.warehouse_id = i.warehouse_id
    INNER JOIN core.product p ON i.product_id = p.product_id AND i.tenant_id = p.tenant_id
    GROUP BY w.warehouse_id, p.product_name;
END;

--
-- Name: inventory_log; Type: TABLE; Schema: inventory_module; Owner: -
--

CREATE TABLE inventory_module.inventory_log (
    inventory_log_id uuid DEFAULT gen_random_uuid() NOT NULL,
    inventory_movement_type_id integer NOT NULL,
    supply_order_id uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
    UPDATE products
    SET stock = stock + NEW.quantity_returned
    WHERE id = NEW.product_id;
    RETURN NEW;
END;

--
-- Name: inventory_log; Type: TABLE; Schema: inventory_module; Owner: -
--

CREATE TABLE inventory_module.inventory_log (
    inventory_log_id uuid DEFAULT gen_random_uuid() NOT NULL,
    inventory_movement_type_id integer NOT NULL,
    supply_order_id uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
    UPDATE products
    SET stock = stock - NEW.quantity_sold
    WHERE id = NEW.product_id;

    -- Check if stock went negative
    IF (SELECT stock FROM products WHERE id = NEW.product_id) < 0 THEN
        RAISE EXCEPTION 'Not enough stock for product ID %', NEW.product_id;
    END IF;

    RETURN NEW;
END;

--
-- Name: inventory_log; Type: TABLE; Schema: inventory_module; Owner: -
--

CREATE TABLE inventory_module.inventory_log (
    inventory_log_id uuid DEFAULT gen_random_uuid() NOT NULL,
    inventory_movement_type_id integer NOT NULL,
    supply_order_id uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE core.branch (
    branch_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    branch_name character varying(100) NOT NULL,
    branch_address text,
    contact_email character varying(100),
    is_main_branch boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: currency; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.currency (
    currency_id integer NOT NULL,
    currency_code character(3) NOT NULL,
    currency_name character varying(50) NOT NULL,
    symbol character varying(10) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: currency_currency_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.currency_currency_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: currency_currency_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.currency_currency_id_seq OWNED BY core.currency.currency_id;


--
-- Name: customer_segment; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.customer_segment (
    customer_segment_id integer NOT NULL,
    segment_name character varying(100) NOT NULL,
    segment_hierarchy integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: customer_segment_customer_segment_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.customer_segment_customer_segment_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customer_segment_customer_segment_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.customer_segment_customer_segment_id_seq OWNED BY core.customer_segment.customer_segment_id;


--
-- Name: customer_segment_margin; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.customer_segment_margin (
    customer_segment_margin_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    customer_segment_id integer NOT NULL,
    customer_segment_margin_type_id integer,
    spending_threshold numeric(10,2),
    seniority_months integer,
    frequency_per_month integer,
    CONSTRAINT customer_segment_margin_frequency_per_month_check CHECK ((frequency_per_month >= 0)),
    CONSTRAINT customer_segment_margin_seniority_months_check CHECK ((seniority_months >= 0)),
    CONSTRAINT customer_segment_margin_spending_threshold_check CHECK ((spending_threshold >= (0)::numeric))
);


--
-- Name: customer_segment_margin_type; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.customer_segment_margin_type (
    customer_segment_margin_type_id integer NOT NULL,
    type_name character varying(50) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: customer_segment_margin_type_customer_segment_margin_type_i_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.customer_segment_margin_type_customer_segment_margin_type_i_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: customer_segment_margin_type_customer_segment_margin_type_i_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.customer_segment_margin_type_customer_segment_margin_type_i_seq OWNED BY core.customer_segment_margin_type.customer_segment_margin_type_id;


--
-- Name: document_type; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.document_type (
    document_type_id integer NOT NULL,
    type_name character varying(50) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: document_type_document_type_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.document_type_document_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: document_type_document_type_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.document_type_document_type_id_seq OWNED BY core.document_type.document_type_id;


--
-- Name: global_attribute; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.global_attribute (
    global_attribute_id integer NOT NULL,
    attribute_name character varying(100) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: global_attribute_global_attribute_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.global_attribute_global_attribute_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: global_attribute_global_attribute_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.global_attribute_global_attribute_id_seq OWNED BY core.global_attribute.global_attribute_id;


--
-- Name: payment_method; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.payment_method (
    payment_method_id integer NOT NULL,
    name character varying(50) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: payment_method_payment_method_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.payment_method_payment_method_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: payment_method_payment_method_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.payment_method_payment_method_id_seq OWNED BY core.payment_method.payment_method_id;


--
-- Name: product; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product (
    tenant_id uuid NOT NULL,
    product_id uuid DEFAULT gen_random_uuid() NOT NULL,
    sku character varying(50) NOT NULL,
    product_name character varying(100) NOT NULL,
    product_name_tsv tsvector GENERATED ALWAYS AS (to_tsvector('spanish'::regconfig, (product_name)::text)) STORED,
    product_description text,
    product_category_id integer,
    unit_price numeric(10,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT product_unit_price_check CHECK ((unit_price >= (0)::numeric))
)
PARTITION BY HASH (tenant_id);


--
-- Name: product_attribute; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_attribute (
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    tenant_attribute_id uuid NOT NULL,
    value text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: product_category; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_category (
    product_category_id integer NOT NULL,
    category_name character varying(100) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: product_category_product_category_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.product_category_product_category_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: product_category_product_category_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.product_category_product_category_id_seq OWNED BY core.product_category.product_category_id;


--
-- Name: product_p0; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_p0 (
    tenant_id uuid NOT NULL,
    product_id uuid DEFAULT gen_random_uuid() NOT NULL,
    sku character varying(50) NOT NULL,
    product_name character varying(100) NOT NULL,
    product_name_tsv tsvector GENERATED ALWAYS AS (to_tsvector('spanish'::regconfig, (product_name)::text)) STORED,
    product_description text,
    product_category_id integer,
    unit_price numeric(10,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT product_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: product_p1; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_p1 (
    tenant_id uuid NOT NULL,
    product_id uuid DEFAULT gen_random_uuid() NOT NULL,
    sku character varying(50) NOT NULL,
    product_name character varying(100) NOT NULL,
    product_name_tsv tsvector GENERATED ALWAYS AS (to_tsvector('spanish'::regconfig, (product_name)::text)) STORED,
    product_description text,
    product_category_id integer,
    unit_price numeric(10,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT product_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: product_p2; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_p2 (
    tenant_id uuid NOT NULL,
    product_id uuid DEFAULT gen_random_uuid() NOT NULL,
    sku character varying(50) NOT NULL,
    product_name character varying(100) NOT NULL,
    product_name_tsv tsvector GENERATED ALWAYS AS (to_tsvector('spanish'::regconfig, (product_name)::text)) STORED,
    product_description text,
    product_category_id integer,
    unit_price numeric(10,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT product_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: product_p3; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_p3 (
    tenant_id uuid NOT NULL,
    product_id uuid DEFAULT gen_random_uuid() NOT NULL,
    sku character varying(50) NOT NULL,
    product_name character varying(100) NOT NULL,
    product_name_tsv tsvector GENERATED ALWAYS AS (to_tsvector('spanish'::regconfig, (product_name)::text)) STORED,
    product_description text,
    product_category_id integer,
    unit_price numeric(10,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT product_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: product_p4; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_p4 (
    tenant_id uuid NOT NULL,
    product_id uuid DEFAULT gen_random_uuid() NOT NULL,
    sku character varying(50) NOT NULL,
    product_name character varying(100) NOT NULL,
    product_name_tsv tsvector GENERATED ALWAYS AS (to_tsvector('spanish'::regconfig, (product_name)::text)) STORED,
    product_description text,
    product_category_id integer,
    unit_price numeric(10,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT product_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: product_p5; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_p5 (
    tenant_id uuid NOT NULL,
    product_id uuid DEFAULT gen_random_uuid() NOT NULL,
    sku character varying(50) NOT NULL,
    product_name character varying(100) NOT NULL,
    product_name_tsv tsvector GENERATED ALWAYS AS (to_tsvector('spanish'::regconfig, (product_name)::text)) STORED,
    product_description text,
    product_category_id integer,
    unit_price numeric(10,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT product_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: product_p6; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_p6 (
    tenant_id uuid NOT NULL,
    product_id uuid DEFAULT gen_random_uuid() NOT NULL,
    sku character varying(50) NOT NULL,
    product_name character varying(100) NOT NULL,
    product_name_tsv tsvector GENERATED ALWAYS AS (to_tsvector('spanish'::regconfig, (product_name)::text)) STORED,
    product_description text,
    product_category_id integer,
    unit_price numeric(10,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT product_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: product_p7; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.product_p7 (
    tenant_id uuid NOT NULL,
    product_id uuid DEFAULT gen_random_uuid() NOT NULL,
    sku character varying(50) NOT NULL,
    product_name character varying(100) NOT NULL,
    product_name_tsv tsvector GENERATED ALWAYS AS (to_tsvector('spanish'::regconfig, (product_name)::text)) STORED,
    product_description text,
    product_category_id integer,
    unit_price numeric(10,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT product_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: region; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.region (
    region_id integer NOT NULL,
    region_name character varying(100) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: region_region_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.region_region_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: region_region_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.region_region_id_seq OWNED BY core.region.region_id;


--
-- Name: role; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.role (
    role_id integer NOT NULL,
    role_name character varying(50) NOT NULL,
    role_hierarchy integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: role_role_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.role_role_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: role_role_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.role_role_id_seq OWNED BY core.role.role_id;


--
-- Name: subscription; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.subscription (
    subscription_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid,
    subscription_type_id integer,
    tenant_payment_id uuid,
    start_date date NOT NULL,
    end_date date NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT subscription_check CHECK ((end_date > start_date))
);


--
-- Name: subscription_type; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.subscription_type (
    subscription_type_id integer NOT NULL,
    subscription_type_name character varying(25) NOT NULL,
    subscription_type_detail text NOT NULL,
    duration_months integer NOT NULL,
    subscription_type_cost numeric(5,2)
);


--
-- Name: subscription_type_subscription_type_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.subscription_type_subscription_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: subscription_type_subscription_type_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.subscription_type_subscription_type_id_seq OWNED BY core.subscription_type.subscription_type_id;


--
-- Name: tax_rate; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.tax_rate (
    tax_rate_id integer NOT NULL,
    region character varying(100) NOT NULL,
    region_id integer,
    rate_percentage numeric(5,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tax_rate_rate_percentage_check CHECK (((rate_percentage >= (0)::numeric) AND (rate_percentage <= (100)::numeric)))
);


--
-- Name: tax_rate_tax_rate_id_seq; Type: SEQUENCE; Schema: core; Owner: -
--

CREATE SEQUENCE core.tax_rate_tax_rate_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: tax_rate_tax_rate_id_seq; Type: SEQUENCE OWNED BY; Schema: core; Owner: -
--

ALTER SEQUENCE core.tax_rate_tax_rate_id_seq OWNED BY core.tax_rate.tax_rate_id;


--
-- Name: tenant; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.tenant (
    tenant_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_name character varying(100) NOT NULL,
    region_id integer,
    contact_email character varying(100) NOT NULL,
    is_subscribed boolean DEFAULT false,
    stripe_id character varying(255) DEFAULT NULL::character varying,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: tenant_attribute; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.tenant_attribute (
    tenant_attribute_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    global_attribute_id integer,
    attribute_name character varying(100) NOT NULL,
    is_custom boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tenant_attribute_check CHECK ((((global_attribute_id IS NOT NULL) AND (is_custom = false)) OR ((global_attribute_id IS NULL) AND (is_custom = true))))
);


--
-- Name: tenant_customer; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.tenant_customer (
    tenant_customer_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    first_name character varying(100) NOT NULL,
    last_name character varying(100) NOT NULL,
    document_type_id integer,
    document_number character varying(50) NOT NULL,
    email character varying(255) NOT NULL,
    phone character varying(50) NOT NULL,
    birthdate date,
    address text,
    customer_segment_id integer DEFAULT 4,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: tenant_payment; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.tenant_payment (
    tenant_payment_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid,
    payment_method_id integer,
    payment_amount numeric(10,2) NOT NULL,
    payment_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    details character varying(255),
    verified boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tenant_payment_payment_amount_check CHECK ((payment_amount >= (0)::numeric))
);


--
-- Name: users; Type: TABLE; Schema: core; Owner: -
--

CREATE TABLE core.users (
    user_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid,
    email character varying(100) NOT NULL,
    password_hash character varying(255) NOT NULL,
    role_id integer,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: inventory; Type: TABLE; Schema: inventory_module; Owner: -
--

CREATE TABLE inventory_module.inventory (
    inventory_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    warehouse_id uuid NOT NULL,
    stock integer NOT NULL,
    expiration_date timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_expiration_date CHECK (((expiration_date IS NULL) OR (expiration_date > CURRENT_TIMESTAMP)))
);


--
-- Name: inventory_log; Type: TABLE; Schema: inventory_module; Owner: -
--

CREATE TABLE inventory_module.inventory_log (
    inventory_log_id uuid DEFAULT gen_random_uuid() NOT NULL,
    inventory_movement_type_id integer NOT NULL,
    supply_order_id uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: inventory_movement_type; Type: TABLE; Schema: inventory_module; Owner: -
--

CREATE TABLE inventory_module.inventory_movement_type (
    inventory_movement_type_id integer NOT NULL,
    inventory_movement_type_name character varying(50) NOT NULL,
    inventory_movement_type_description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: inventory_movement_type_inventory_movement_type_id_seq; Type: SEQUENCE; Schema: inventory_module; Owner: -
--

CREATE SEQUENCE inventory_module.inventory_movement_type_inventory_movement_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: inventory_movement_type_inventory_movement_type_id_seq; Type: SEQUENCE OWNED BY; Schema: inventory_module; Owner: -
--

ALTER SEQUENCE inventory_module.inventory_movement_type_inventory_movement_type_id_seq OWNED BY inventory_module.inventory_movement_type.inventory_movement_type_id;


--
-- Name: inventory_transfer; Type: TABLE; Schema: inventory_module; Owner: -
--

CREATE TABLE inventory_module.inventory_transfer (
    inventory_transfer_id uuid DEFAULT gen_random_uuid() NOT NULL,
    from_warehouse_id uuid NOT NULL,
    to_warehouse_id uuid NOT NULL,
    inventory_transfer_departure_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    inventory_transfer_arrival_date timestamp without time zone,
    transfer_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: inventory_transfer_product; Type: TABLE; Schema: inventory_module; Owner: -
--

CREATE TABLE inventory_module.inventory_transfer_product (
    inventory_transfer_product_id uuid DEFAULT gen_random_uuid() NOT NULL,
    inventory_transfer_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: warehouse; Type: TABLE; Schema: inventory_module; Owner: -
--

CREATE TABLE inventory_module.warehouse (
    warehouse_id uuid DEFAULT gen_random_uuid() NOT NULL,
    branch_id uuid NOT NULL,
    warehouse_name character varying(255) NOT NULL,
    warehouse_address text NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: bill; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.bill (
    bill_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_customer_id uuid,
    sale_id uuid NOT NULL,
    currency_id integer,
    subtotal_amount numeric(10,2) NOT NULL,
    tax_amount numeric(10,2) NOT NULL,
    total_amount numeric(10,2) NOT NULL,
    billed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT bill_subtotal_amount_check CHECK ((subtotal_amount >= (0)::numeric)),
    CONSTRAINT bill_tax_amount_check CHECK ((tax_amount >= (0)::numeric))
);


--
-- Name: bill_payment; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.bill_payment (
    bill_payment_id uuid DEFAULT gen_random_uuid() NOT NULL,
    bill_id uuid NOT NULL,
    customer_payment_id uuid NOT NULL,
    payment_amount numeric(10,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT bill_payment_payment_amount_check CHECK ((payment_amount > (0)::numeric))
);


--
-- Name: cash_register; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.cash_register (
    cash_register_id uuid DEFAULT gen_random_uuid() NOT NULL,
    branch_id uuid NOT NULL,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: cash_register_sale; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.cash_register_sale (
    cash_register_sale_id uuid DEFAULT gen_random_uuid() NOT NULL,
    cash_register_session_id uuid NOT NULL,
    sale_id uuid NOT NULL,
    transaction_time timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: cash_register_session; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.cash_register_session (
    cash_register_session_id uuid DEFAULT gen_random_uuid() NOT NULL,
    cash_register_id uuid NOT NULL,
    user_id uuid NOT NULL,
    opened_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    closed_at timestamp without time zone,
    opening_amount numeric(10,2) NOT NULL,
    closing_amount numeric(10,2),
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT cash_register_session_closing_amount_check CHECK ((closing_amount >= (0)::numeric)),
    CONSTRAINT cash_register_session_opening_amount_check CHECK ((opening_amount >= (0)::numeric))
);


--
-- Name: customer_payment; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.customer_payment (
    customer_payment_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_customer_id uuid NOT NULL,
    sale_id uuid NOT NULL,
    payment_method_id integer,
    is_points_redemption boolean DEFAULT false,
    points_redeemed integer DEFAULT 0,
    points_to_currency_rate numeric(10,4) DEFAULT 0,
    payment_amount numeric(10,2) NOT NULL,
    payment_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    currency_id integer,
    verified boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT check_points_redemption CHECK ((((is_points_redemption = true) AND (points_redeemed IS NOT NULL) AND (points_redeemed > 0) AND (payment_method_id = 4)) OR (is_points_redemption = false))),
    CONSTRAINT customer_payment_payment_amount_check CHECK ((payment_amount > (0)::numeric)),
    CONSTRAINT customer_payment_points_redeemed_check CHECK ((points_redeemed >= 0)),
    CONSTRAINT customer_payment_points_to_currency_rate_check CHECK ((points_to_currency_rate >= (0)::numeric))
);


--
-- Name: loyalty_program; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.loyalty_program (
    loyalty_program_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    points_earned_per_currency_unit numeric(5,2) DEFAULT 1.00 NOT NULL,
    points_redeemed_per_currency_unit numeric(10,2) DEFAULT 100.00 NOT NULL,
    minimum_purchase_for_points numeric(10,2) DEFAULT 0,
    is_active boolean DEFAULT true,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT loyalty_program_minimum_purchase_for_points_check CHECK ((minimum_purchase_for_points >= (0)::numeric)),
    CONSTRAINT loyalty_program_points_earned_per_currency_unit_check CHECK ((points_earned_per_currency_unit >= (0)::numeric)),
    CONSTRAINT loyalty_program_points_redeemed_per_currency_unit_check CHECK ((points_redeemed_per_currency_unit > (0)::numeric))
);


--
-- Name: promotion; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.promotion (
    promotion_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    promotion_name character varying(100) NOT NULL,
    promotion_code character varying(50) NOT NULL,
    promotion_description text,
    promotion_type_id integer,
    customer_segment_id integer,
    promotion_start_date date NOT NULL,
    promotion_end_date date NOT NULL,
    is_active boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT promotion_check CHECK ((promotion_end_date > promotion_start_date))
);


--
-- Name: promotion_rule; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.promotion_rule (
    promotion_rule_id uuid DEFAULT gen_random_uuid() NOT NULL,
    promotion_id uuid NOT NULL,
    discount_percentage numeric(5,2),
    discount_amount numeric(10,2),
    buy_quantity integer,
    get_quantity integer,
    get_discount_percentage numeric(5,2) DEFAULT 100.00,
    min_quantity integer,
    max_quantity integer,
    tier_level integer,
    tier_min_quantity integer,
    tier_max_quantity integer,
    tier_price numeric(10,2),
    tier_discount_percentage numeric(5,2),
    min_purchase_amount numeric(10,2),
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT promotion_rule_discount_amount_check CHECK (((discount_amount IS NULL) OR (discount_amount >= (0)::numeric))),
    CONSTRAINT promotion_rule_discount_percentage_check CHECK (((discount_percentage IS NULL) OR ((discount_percentage >= (0)::numeric) AND (discount_percentage <= (100)::numeric)))),
    CONSTRAINT promotion_rule_get_discount_percentage_check CHECK (((get_discount_percentage IS NULL) OR ((get_discount_percentage >= (0)::numeric) AND (get_discount_percentage <= (100)::numeric))))
);


--
-- Name: promotion_type; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.promotion_type (
    promotion_type_id integer NOT NULL,
    type_name character varying(50) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: promotion_type_promotion_type_id_seq; Type: SEQUENCE; Schema: pos_module; Owner: -
--

CREATE SEQUENCE pos_module.promotion_type_promotion_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: promotion_type_promotion_type_id_seq; Type: SEQUENCE OWNED BY; Schema: pos_module; Owner: -
--

ALTER SEQUENCE pos_module.promotion_type_promotion_type_id_seq OWNED BY pos_module.promotion_type.promotion_type_id;


--
-- Name: return_product; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.return_product (
    return_product_id uuid DEFAULT gen_random_uuid() NOT NULL,
    return_transaction_id uuid NOT NULL,
    sale_item_id uuid NOT NULL,
    quantity integer NOT NULL,
    unit_price numeric(10,2) NOT NULL,
    total_price numeric(10,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT return_product_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT return_product_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: return_reason; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.return_reason (
    return_reason_id integer NOT NULL,
    reason_code character varying(50) NOT NULL,
    reason_name character varying(100) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: return_reason_return_reason_id_seq; Type: SEQUENCE; Schema: pos_module; Owner: -
--

CREATE SEQUENCE pos_module.return_reason_return_reason_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: return_reason_return_reason_id_seq; Type: SEQUENCE OWNED BY; Schema: pos_module; Owner: -
--

ALTER SEQUENCE pos_module.return_reason_return_reason_id_seq OWNED BY pos_module.return_reason.return_reason_id;


--
-- Name: return_status; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.return_status (
    return_status_id integer NOT NULL,
    status_name character varying(50) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: return_status_return_status_id_seq; Type: SEQUENCE; Schema: pos_module; Owner: -
--

CREATE SEQUENCE pos_module.return_status_return_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: return_status_return_status_id_seq; Type: SEQUENCE OWNED BY; Schema: pos_module; Owner: -
--

ALTER SEQUENCE pos_module.return_status_return_status_id_seq OWNED BY pos_module.return_status.return_status_id;


--
-- Name: return_transaction; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.return_transaction (
    return_transaction_id uuid DEFAULT gen_random_uuid() NOT NULL,
    bill_id uuid NOT NULL,
    tenant_customer_id uuid,
    total_refund_amount numeric(10,2) NOT NULL,
    refund_method integer,
    return_status_id integer,
    return_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT return_transaction_total_refund_amount_check CHECK ((total_refund_amount >= (0)::numeric))
);


--
-- Name: sale; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.sale (
    sale_id uuid DEFAULT gen_random_uuid() NOT NULL,
    branch_id uuid NOT NULL,
    sale_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    currency_id integer,
    subtotal_amount numeric(10,2) DEFAULT 0 NOT NULL,
    tax_amount numeric(10,2) DEFAULT 0 NOT NULL,
    total_amount numeric(10,2) NOT NULL,
    is_completed boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT sale_subtotal_amount_check CHECK ((subtotal_amount >= (0)::numeric)),
    CONSTRAINT sale_tax_amount_check CHECK ((tax_amount >= (0)::numeric))
);


--
-- Name: sale_item; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.sale_item (
    sale_item_id uuid DEFAULT gen_random_uuid() NOT NULL,
    sale_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity integer NOT NULL,
    unit_price numeric(10,2) NOT NULL,
    total_price numeric(10,2) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT sale_item_quantity_check CHECK ((quantity > 0)),
    CONSTRAINT sale_item_unit_price_check CHECK ((unit_price >= (0)::numeric))
);


--
-- Name: score_redemption_status; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.score_redemption_status (
    score_redemption_status_id integer NOT NULL,
    status_name character varying(50) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: score_redemption_status_score_redemption_status_id_seq; Type: SEQUENCE; Schema: pos_module; Owner: -
--

CREATE SEQUENCE pos_module.score_redemption_status_score_redemption_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: score_redemption_status_score_redemption_status_id_seq; Type: SEQUENCE OWNED BY; Schema: pos_module; Owner: -
--

ALTER SEQUENCE pos_module.score_redemption_status_score_redemption_status_id_seq OWNED BY pos_module.score_redemption_status.score_redemption_status_id;


--
-- Name: score_transaction; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.score_transaction (
    score_transaction_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    tenant_customer_id uuid NOT NULL,
    transaction_type_id integer,
    points integer NOT NULL,
    bill_id uuid,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: score_transaction_type; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.score_transaction_type (
    score_transaction_type_id integer NOT NULL,
    type_name character varying(50) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: score_transaction_type_score_transaction_type_id_seq; Type: SEQUENCE; Schema: pos_module; Owner: -
--

CREATE SEQUENCE pos_module.score_transaction_type_score_transaction_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: score_transaction_type_score_transaction_type_id_seq; Type: SEQUENCE OWNED BY; Schema: pos_module; Owner: -
--

ALTER SEQUENCE pos_module.score_transaction_type_score_transaction_type_id_seq OWNED BY pos_module.score_transaction_type.score_transaction_type_id;


--
-- Name: tenant_customer_score; Type: TABLE; Schema: pos_module; Owner: -
--

CREATE TABLE pos_module.tenant_customer_score (
    tenant_id uuid NOT NULL,
    tenant_customer_id uuid NOT NULL,
    score integer DEFAULT 0 NOT NULL,
    lifetime_score integer DEFAULT 0 NOT NULL,
    score_redeemed integer DEFAULT 0 NOT NULL,
    last_earned_at timestamp without time zone,
    last_redeemed_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT tenant_customer_score_lifetime_score_check CHECK ((lifetime_score >= 0)),
    CONSTRAINT tenant_customer_score_score_check CHECK ((score >= 0)),
    CONSTRAINT tenant_customer_score_score_redeemed_check CHECK ((score_redeemed >= 0))
);


--
-- Name: account_payable; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.account_payable (
    account_payable_id uuid DEFAULT gen_random_uuid() NOT NULL,
    supply_order_id uuid NOT NULL,
    has_invoice boolean DEFAULT true,
    subtotal_amount numeric(12,3) DEFAULT 0,
    tax_amount numeric(12,3) DEFAULT 0,
    amount_due numeric(12,3) GENERATED ALWAYS AS ((subtotal_amount + tax_amount)) STORED,
    amount_paid numeric(12,3) DEFAULT 0,
    balance_remaining numeric(12,3) GENERATED ALWAYS AS (((subtotal_amount + tax_amount) - amount_paid)) STORED,
    due_date date NOT NULL,
    account_status integer DEFAULT 1 NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: account_payable_status; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.account_payable_status (
    status_id integer NOT NULL,
    status_name character varying(50) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: account_payable_status_status_id_seq; Type: SEQUENCE; Schema: supplies_module; Owner: -
--

CREATE SEQUENCE supplies_module.account_payable_status_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: account_payable_status_status_id_seq; Type: SEQUENCE OWNED BY; Schema: supplies_module; Owner: -
--

ALTER SEQUENCE supplies_module.account_payable_status_status_id_seq OWNED BY supplies_module.account_payable_status.status_id;


--
-- Name: goods_receipt; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.goods_receipt (
    goods_receipt_id uuid DEFAULT gen_random_uuid() NOT NULL,
    supply_order_id uuid NOT NULL,
    received_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    subtotal_amount numeric(12,3) DEFAULT 0,
    tax_amount numeric(12,3) DEFAULT 0,
    total_amount numeric(12,3) GENERATED ALWAYS AS ((subtotal_amount + tax_amount)) STORED,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: goods_receipt_item; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.goods_receipt_item (
    goods_receipt_item_id uuid DEFAULT gen_random_uuid() NOT NULL,
    goods_receipt_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity_received integer NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: supplier; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.supplier (
    supplier_id uuid DEFAULT gen_random_uuid() NOT NULL,
    supplier_name character varying(255) NOT NULL,
    supplier_contact_info text,
    supplier_address text,
    supplier_notes text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: supplier_branch; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.supplier_branch (
    supplier_branch_id uuid DEFAULT gen_random_uuid() NOT NULL,
    supplier_id uuid NOT NULL,
    branch_id uuid NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: supplier_invoice; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.supplier_invoice (
    supplier_invoice_id uuid DEFAULT gen_random_uuid() NOT NULL,
    supply_order_id uuid NOT NULL,
    invoice_number character varying(100) NOT NULL,
    invoice_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    payment_condition character varying(10) DEFAULT 'CREDIT'::character varying NOT NULL,
    due_date date,
    subtotal_amount numeric(12,3) NOT NULL,
    tax_rate numeric(5,2) DEFAULT 13.00 NOT NULL,
    tax_amount numeric(12,3) GENERATED ALWAYS AS (round((subtotal_amount * (tax_rate / (100)::numeric)), 3)) STORED,
    total_amount numeric(12,3) GENERATED ALWAYS AS ((subtotal_amount + round((subtotal_amount * (tax_rate / (100)::numeric)), 3))) STORED,
    paid boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT supplier_invoice_payment_condition_check CHECK (((payment_condition)::text = ANY ((ARRAY['CREDIT'::character varying, 'IN_FULL'::character varying])::text[])))
);


--
-- Name: supplier_invoice_item; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.supplier_invoice_item (
    supplier_invoice_item_id uuid DEFAULT gen_random_uuid() NOT NULL,
    supplier_invoice_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity_billed integer NOT NULL,
    unit_price numeric(12,3) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: supply_order; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.supply_order (
    supply_order_id uuid DEFAULT gen_random_uuid() NOT NULL,
    supplier_id uuid NOT NULL,
    warehouse_id uuid NOT NULL,
    supply_order_date date DEFAULT CURRENT_DATE,
    expected_delivery_date date,
    supply_order_status_id integer DEFAULT 1 NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: supply_order_item; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.supply_order_item (
    supply_order_item_id uuid DEFAULT gen_random_uuid() NOT NULL,
    supply_order_id uuid NOT NULL,
    tenant_id uuid NOT NULL,
    product_id uuid NOT NULL,
    quantity_ordered integer NOT NULL,
    unit_price numeric(12,3) NOT NULL,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: supply_order_payment; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.supply_order_payment (
    payment_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    account_payable_id uuid NOT NULL,
    payment_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    amount_paid numeric(12,3) NOT NULL,
    payment_method_id integer NOT NULL,
    payment_reference character varying(100),
    verified boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: supply_order_payment_alert; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.supply_order_payment_alert (
    payment_alert_id uuid DEFAULT gen_random_uuid() NOT NULL,
    account_payable_id uuid NOT NULL,
    payment_alert_type_id integer NOT NULL,
    alert_date timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    is_resolved boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: supply_order_payment_alert_config; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.supply_order_payment_alert_config (
    payment_alert_config_id uuid DEFAULT gen_random_uuid() NOT NULL,
    tenant_id uuid NOT NULL,
    warning_days_before_due integer DEFAULT 7,
    urgent_days_before_due integer DEFAULT 3,
    email_notifications_enabled boolean DEFAULT true,
    sms_notifications_enabled boolean DEFAULT false,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: supply_order_payment_alert_type; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.supply_order_payment_alert_type (
    payment_alert_type_id integer NOT NULL,
    payment_alert_type_name character varying(50) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: supply_order_payment_alert_type_payment_alert_type_id_seq; Type: SEQUENCE; Schema: supplies_module; Owner: -
--

CREATE SEQUENCE supplies_module.supply_order_payment_alert_type_payment_alert_type_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: supply_order_payment_alert_type_payment_alert_type_id_seq; Type: SEQUENCE OWNED BY; Schema: supplies_module; Owner: -
--

ALTER SEQUENCE supplies_module.supply_order_payment_alert_type_payment_alert_type_id_seq OWNED BY supplies_module.supply_order_payment_alert_type.payment_alert_type_id;


--
-- Name: supply_order_status; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.supply_order_status (
    status_id integer NOT NULL,
    status_name character varying(50) NOT NULL,
    description text,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: supply_order_status_status_id_seq; Type: SEQUENCE; Schema: supplies_module; Owner: -
--

CREATE SEQUENCE supplies_module.supply_order_status_status_id_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: supply_order_status_status_id_seq; Type: SEQUENCE OWNED BY; Schema: supplies_module; Owner: -
--

ALTER SEQUENCE supplies_module.supply_order_status_status_id_seq OWNED BY supplies_module.supply_order_status.status_id;


--
-- Name: supply_order_tracking; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.supply_order_tracking (
    supply_order_tracking_id uuid DEFAULT gen_random_uuid() NOT NULL,
    supply_order_id uuid NOT NULL,
    previous_status_id integer,
    new_status_id integer NOT NULL,
    notes text,
    changed_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: three_way_matching; Type: TABLE; Schema: supplies_module; Owner: -
--

CREATE TABLE supplies_module.three_way_matching (
    matching_id uuid DEFAULT gen_random_uuid() NOT NULL,
    supply_order_id uuid NOT NULL,
    goods_receipt_id uuid NOT NULL,
    supplier_invoice_id uuid NOT NULL,
    amounts_matched boolean DEFAULT false,
    quantities_matched boolean DEFAULT false,
    is_matched boolean DEFAULT false,
    matched_at timestamp without time zone,
    created_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP,
    updated_at timestamp without time zone DEFAULT CURRENT_TIMESTAMP
);


--
-- Name: product_p0; Type: TABLE ATTACH; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product ATTACH PARTITION core.product_p0 FOR VALUES WITH (modulus 8, remainder 0);


--
-- Name: product_p1; Type: TABLE ATTACH; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product ATTACH PARTITION core.product_p1 FOR VALUES WITH (modulus 8, remainder 1);


--
-- Name: product_p2; Type: TABLE ATTACH; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product ATTACH PARTITION core.product_p2 FOR VALUES WITH (modulus 8, remainder 2);


--
-- Name: product_p3; Type: TABLE ATTACH; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product ATTACH PARTITION core.product_p3 FOR VALUES WITH (modulus 8, remainder 3);


--
-- Name: product_p4; Type: TABLE ATTACH; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product ATTACH PARTITION core.product_p4 FOR VALUES WITH (modulus 8, remainder 4);


--
-- Name: product_p5; Type: TABLE ATTACH; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product ATTACH PARTITION core.product_p5 FOR VALUES WITH (modulus 8, remainder 5);


--
-- Name: product_p6; Type: TABLE ATTACH; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product ATTACH PARTITION core.product_p6 FOR VALUES WITH (modulus 8, remainder 6);


--
-- Name: product_p7; Type: TABLE ATTACH; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product ATTACH PARTITION core.product_p7 FOR VALUES WITH (modulus 8, remainder 7);


--
-- Name: currency currency_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.currency ALTER COLUMN currency_id SET DEFAULT nextval('core.currency_currency_id_seq'::regclass);


--
-- Name: customer_segment customer_segment_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_segment ALTER COLUMN customer_segment_id SET DEFAULT nextval('core.customer_segment_customer_segment_id_seq'::regclass);


--
-- Name: customer_segment_margin_type customer_segment_margin_type_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_segment_margin_type ALTER COLUMN customer_segment_margin_type_id SET DEFAULT nextval('core.customer_segment_margin_type_customer_segment_margin_type_i_seq'::regclass);


--
-- Name: document_type document_type_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.document_type ALTER COLUMN document_type_id SET DEFAULT nextval('core.document_type_document_type_id_seq'::regclass);


--
-- Name: global_attribute global_attribute_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.global_attribute ALTER COLUMN global_attribute_id SET DEFAULT nextval('core.global_attribute_global_attribute_id_seq'::regclass);


--
-- Name: payment_method payment_method_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.payment_method ALTER COLUMN payment_method_id SET DEFAULT nextval('core.payment_method_payment_method_id_seq'::regclass);


--
-- Name: product_category product_category_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_category ALTER COLUMN product_category_id SET DEFAULT nextval('core.product_category_product_category_id_seq'::regclass);


--
-- Name: region region_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.region ALTER COLUMN region_id SET DEFAULT nextval('core.region_region_id_seq'::regclass);


--
-- Name: role role_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.role ALTER COLUMN role_id SET DEFAULT nextval('core.role_role_id_seq'::regclass);


--
-- Name: subscription_type subscription_type_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.subscription_type ALTER COLUMN subscription_type_id SET DEFAULT nextval('core.subscription_type_subscription_type_id_seq'::regclass);


--
-- Name: tax_rate tax_rate_id; Type: DEFAULT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tax_rate ALTER COLUMN tax_rate_id SET DEFAULT nextval('core.tax_rate_tax_rate_id_seq'::regclass);


--
-- Name: inventory_movement_type inventory_movement_type_id; Type: DEFAULT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.inventory_movement_type ALTER COLUMN inventory_movement_type_id SET DEFAULT nextval('inventory_module.inventory_movement_type_inventory_movement_type_id_seq'::regclass);


--
-- Name: promotion_type promotion_type_id; Type: DEFAULT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.promotion_type ALTER COLUMN promotion_type_id SET DEFAULT nextval('pos_module.promotion_type_promotion_type_id_seq'::regclass);


--
-- Name: return_reason return_reason_id; Type: DEFAULT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.return_reason ALTER COLUMN return_reason_id SET DEFAULT nextval('pos_module.return_reason_return_reason_id_seq'::regclass);


--
-- Name: return_status return_status_id; Type: DEFAULT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.return_status ALTER COLUMN return_status_id SET DEFAULT nextval('pos_module.return_status_return_status_id_seq'::regclass);


--
-- Name: score_redemption_status score_redemption_status_id; Type: DEFAULT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.score_redemption_status ALTER COLUMN score_redemption_status_id SET DEFAULT nextval('pos_module.score_redemption_status_score_redemption_status_id_seq'::regclass);


--
-- Name: score_transaction_type score_transaction_type_id; Type: DEFAULT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.score_transaction_type ALTER COLUMN score_transaction_type_id SET DEFAULT nextval('pos_module.score_transaction_type_score_transaction_type_id_seq'::regclass);


--
-- Name: account_payable_status status_id; Type: DEFAULT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.account_payable_status ALTER COLUMN status_id SET DEFAULT nextval('supplies_module.account_payable_status_status_id_seq'::regclass);


--
-- Name: supply_order_payment_alert_type payment_alert_type_id; Type: DEFAULT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_payment_alert_type ALTER COLUMN payment_alert_type_id SET DEFAULT nextval('supplies_module.supply_order_payment_alert_type_payment_alert_type_id_seq'::regclass);


--
-- Name: supply_order_status status_id; Type: DEFAULT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_status ALTER COLUMN status_id SET DEFAULT nextval('supplies_module.supply_order_status_status_id_seq'::regclass);


--
-- Name: branch branch_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.branch
    ADD CONSTRAINT branch_pkey PRIMARY KEY (branch_id);


--
-- Name: currency currency_currency_code_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.currency
    ADD CONSTRAINT currency_currency_code_key UNIQUE (currency_code);


--
-- Name: currency currency_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.currency
    ADD CONSTRAINT currency_pkey PRIMARY KEY (currency_id);


--
-- Name: customer_segment_margin customer_segment_margin_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_segment_margin
    ADD CONSTRAINT customer_segment_margin_pkey PRIMARY KEY (customer_segment_margin_id);


--
-- Name: customer_segment_margin_type customer_segment_margin_type_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_segment_margin_type
    ADD CONSTRAINT customer_segment_margin_type_pkey PRIMARY KEY (customer_segment_margin_type_id);


--
-- Name: customer_segment_margin_type customer_segment_margin_type_type_name_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_segment_margin_type
    ADD CONSTRAINT customer_segment_margin_type_type_name_key UNIQUE (type_name);


--
-- Name: customer_segment customer_segment_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_segment
    ADD CONSTRAINT customer_segment_pkey PRIMARY KEY (customer_segment_id);


--
-- Name: customer_segment customer_segment_segment_name_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_segment
    ADD CONSTRAINT customer_segment_segment_name_key UNIQUE (segment_name);


--
-- Name: document_type document_type_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.document_type
    ADD CONSTRAINT document_type_pkey PRIMARY KEY (document_type_id);


--
-- Name: document_type document_type_type_name_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.document_type
    ADD CONSTRAINT document_type_type_name_key UNIQUE (type_name);


--
-- Name: global_attribute global_attribute_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.global_attribute
    ADD CONSTRAINT global_attribute_pkey PRIMARY KEY (global_attribute_id);


--
-- Name: payment_method payment_method_name_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.payment_method
    ADD CONSTRAINT payment_method_name_key UNIQUE (name);


--
-- Name: payment_method payment_method_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.payment_method
    ADD CONSTRAINT payment_method_pkey PRIMARY KEY (payment_method_id);


--
-- Name: product_attribute product_attribute_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_attribute
    ADD CONSTRAINT product_attribute_pkey PRIMARY KEY (tenant_id, product_id, tenant_attribute_id);


--
-- Name: product_category product_category_category_name_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_category
    ADD CONSTRAINT product_category_category_name_key UNIQUE (category_name);


--
-- Name: product_category product_category_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_category
    ADD CONSTRAINT product_category_pkey PRIMARY KEY (product_category_id);


--
-- Name: product product_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product
    ADD CONSTRAINT product_pkey PRIMARY KEY (tenant_id, product_id);


--
-- Name: product_p0 product_p0_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_p0
    ADD CONSTRAINT product_p0_pkey PRIMARY KEY (tenant_id, product_id);


--
-- Name: product_p1 product_p1_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_p1
    ADD CONSTRAINT product_p1_pkey PRIMARY KEY (tenant_id, product_id);


--
-- Name: product_p2 product_p2_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_p2
    ADD CONSTRAINT product_p2_pkey PRIMARY KEY (tenant_id, product_id);


--
-- Name: product_p3 product_p3_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_p3
    ADD CONSTRAINT product_p3_pkey PRIMARY KEY (tenant_id, product_id);


--
-- Name: product_p4 product_p4_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_p4
    ADD CONSTRAINT product_p4_pkey PRIMARY KEY (tenant_id, product_id);


--
-- Name: product_p5 product_p5_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_p5
    ADD CONSTRAINT product_p5_pkey PRIMARY KEY (tenant_id, product_id);


--
-- Name: product_p6 product_p6_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_p6
    ADD CONSTRAINT product_p6_pkey PRIMARY KEY (tenant_id, product_id);


--
-- Name: product_p7 product_p7_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_p7
    ADD CONSTRAINT product_p7_pkey PRIMARY KEY (tenant_id, product_id);


--
-- Name: region region_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.region
    ADD CONSTRAINT region_pkey PRIMARY KEY (region_id);


--
-- Name: region region_region_name_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.region
    ADD CONSTRAINT region_region_name_key UNIQUE (region_name);


--
-- Name: role role_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.role
    ADD CONSTRAINT role_pkey PRIMARY KEY (role_id);


--
-- Name: role role_role_name_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.role
    ADD CONSTRAINT role_role_name_key UNIQUE (role_name);


--
-- Name: subscription subscription_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.subscription
    ADD CONSTRAINT subscription_pkey PRIMARY KEY (subscription_id);


--
-- Name: subscription_type subscription_type_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.subscription_type
    ADD CONSTRAINT subscription_type_pkey PRIMARY KEY (subscription_type_id);


--
-- Name: tax_rate tax_rate_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tax_rate
    ADD CONSTRAINT tax_rate_pkey PRIMARY KEY (tax_rate_id);


--
-- Name: tax_rate tax_rate_region_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tax_rate
    ADD CONSTRAINT tax_rate_region_key UNIQUE (region);


--
-- Name: tenant_attribute tenant_attribute_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant_attribute
    ADD CONSTRAINT tenant_attribute_pkey PRIMARY KEY (tenant_attribute_id);


--
-- Name: tenant_customer tenant_customer_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant_customer
    ADD CONSTRAINT tenant_customer_pkey PRIMARY KEY (tenant_customer_id);


--
-- Name: tenant_customer tenant_customer_tenant_id_document_number_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant_customer
    ADD CONSTRAINT tenant_customer_tenant_id_document_number_key UNIQUE (tenant_id, document_number);


--
-- Name: tenant_customer tenant_customer_tenant_id_email_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant_customer
    ADD CONSTRAINT tenant_customer_tenant_id_email_key UNIQUE (tenant_id, email);


--
-- Name: tenant_customer tenant_customer_tenant_id_phone_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant_customer
    ADD CONSTRAINT tenant_customer_tenant_id_phone_key UNIQUE (tenant_id, phone);


--
-- Name: tenant_payment tenant_payment_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant_payment
    ADD CONSTRAINT tenant_payment_pkey PRIMARY KEY (tenant_payment_id);


--
-- Name: tenant tenant_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant
    ADD CONSTRAINT tenant_pkey PRIMARY KEY (tenant_id);


--
-- Name: tenant tenant_stripe_id_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant
    ADD CONSTRAINT tenant_stripe_id_key UNIQUE (stripe_id);


--
-- Name: tenant tenant_tenant_name_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant
    ADD CONSTRAINT tenant_tenant_name_key UNIQUE (tenant_name);


--
-- Name: users users_email_key; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.users
    ADD CONSTRAINT users_email_key UNIQUE (email);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (user_id);


--
-- Name: inventory_movement inventory_movement_pkey; Type: CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.inventory_log
    ADD CONSTRAINT inventory_log_pkey PRIMARY KEY (inventory_log_id);


--
-- Name: inventory_movement_type inventory_movement_type_inventory_movement_type_name_key; Type: CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.inventory_movement_type
    ADD CONSTRAINT inventory_movement_type_inventory_movement_type_name_key UNIQUE (inventory_movement_type_name);


--
-- Name: inventory_movement_type inventory_movement_type_pkey; Type: CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.inventory_movement_type
    ADD CONSTRAINT inventory_movement_type_pkey PRIMARY KEY (inventory_movement_type_id);


--
-- Name: inventory inventory_pkey; Type: CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.inventory
    ADD CONSTRAINT inventory_pkey PRIMARY KEY (inventory_id);


--
-- Name: inventory_transfer inventory_transfer_pkey; Type: CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.inventory_transfer
    ADD CONSTRAINT inventory_transfer_pkey PRIMARY KEY (inventory_transfer_id);


--
-- Name: inventory_transfer_product inventory_transfer_product_pkey; Type: CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.inventory_transfer_product
    ADD CONSTRAINT inventory_transfer_product_pkey PRIMARY KEY (inventory_transfer_product_id);


--
-- Name: warehouse warehouse_pkey; Type: CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.warehouse
    ADD CONSTRAINT warehouse_pkey PRIMARY KEY (warehouse_id);


--
-- Name: bill_payment bill_payment_bill_id_customer_payment_id_key; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.bill_payment
    ADD CONSTRAINT bill_payment_bill_id_customer_payment_id_key UNIQUE (bill_id, customer_payment_id);


--
-- Name: bill_payment bill_payment_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.bill_payment
    ADD CONSTRAINT bill_payment_pkey PRIMARY KEY (bill_payment_id);


--
-- Name: bill bill_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.bill
    ADD CONSTRAINT bill_pkey PRIMARY KEY (bill_id);


--
-- Name: cash_register cash_register_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.cash_register
    ADD CONSTRAINT cash_register_pkey PRIMARY KEY (cash_register_id);


--
-- Name: cash_register_sale cash_register_sale_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.cash_register_sale
    ADD CONSTRAINT cash_register_sale_pkey PRIMARY KEY (cash_register_sale_id);


--
-- Name: cash_register_sale cash_register_sale_sale_id_key; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.cash_register_sale
    ADD CONSTRAINT cash_register_sale_sale_id_key UNIQUE (sale_id);


--
-- Name: cash_register_session cash_register_session_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.cash_register_session
    ADD CONSTRAINT cash_register_session_pkey PRIMARY KEY (cash_register_session_id);


--
-- Name: customer_payment customer_payment_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.customer_payment
    ADD CONSTRAINT customer_payment_pkey PRIMARY KEY (customer_payment_id);


--
-- Name: loyalty_program loyalty_program_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.loyalty_program
    ADD CONSTRAINT loyalty_program_pkey PRIMARY KEY (loyalty_program_id);


--
-- Name: promotion promotion_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.promotion
    ADD CONSTRAINT promotion_pkey PRIMARY KEY (promotion_id);


--
-- Name: promotion_rule promotion_rule_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.promotion_rule
    ADD CONSTRAINT promotion_rule_pkey PRIMARY KEY (promotion_rule_id);


--
-- Name: promotion_type promotion_type_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.promotion_type
    ADD CONSTRAINT promotion_type_pkey PRIMARY KEY (promotion_type_id);


--
-- Name: promotion_type promotion_type_type_name_key; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.promotion_type
    ADD CONSTRAINT promotion_type_type_name_key UNIQUE (type_name);


--
-- Name: return_product return_product_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.return_product
    ADD CONSTRAINT return_product_pkey PRIMARY KEY (return_product_id);


--
-- Name: return_reason return_reason_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.return_reason
    ADD CONSTRAINT return_reason_pkey PRIMARY KEY (return_reason_id);


--
-- Name: return_reason return_reason_reason_code_key; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.return_reason
    ADD CONSTRAINT return_reason_reason_code_key UNIQUE (reason_code);


--
-- Name: return_status return_status_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.return_status
    ADD CONSTRAINT return_status_pkey PRIMARY KEY (return_status_id);


--
-- Name: return_status return_status_status_name_key; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.return_status
    ADD CONSTRAINT return_status_status_name_key UNIQUE (status_name);


--
-- Name: return_transaction return_transaction_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.return_transaction
    ADD CONSTRAINT return_transaction_pkey PRIMARY KEY (return_transaction_id);


--
-- Name: sale_item sale_item_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.sale_item
    ADD CONSTRAINT sale_item_pkey PRIMARY KEY (sale_item_id);


--
-- Name: sale sale_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.sale
    ADD CONSTRAINT sale_pkey PRIMARY KEY (sale_id);


--
-- Name: score_redemption_status score_redemption_status_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.score_redemption_status
    ADD CONSTRAINT score_redemption_status_pkey PRIMARY KEY (score_redemption_status_id);


--
-- Name: score_redemption_status score_redemption_status_status_name_key; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.score_redemption_status
    ADD CONSTRAINT score_redemption_status_status_name_key UNIQUE (status_name);


--
-- Name: score_transaction score_transaction_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.score_transaction
    ADD CONSTRAINT score_transaction_pkey PRIMARY KEY (score_transaction_id);


--
-- Name: score_transaction_type score_transaction_type_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.score_transaction_type
    ADD CONSTRAINT score_transaction_type_pkey PRIMARY KEY (score_transaction_type_id);


--
-- Name: score_transaction_type score_transaction_type_type_name_key; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.score_transaction_type
    ADD CONSTRAINT score_transaction_type_type_name_key UNIQUE (type_name);


--
-- Name: tenant_customer_score tenant_customer_score_pkey; Type: CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.tenant_customer_score
    ADD CONSTRAINT tenant_customer_score_pkey PRIMARY KEY (tenant_customer_id, tenant_id);


--
-- Name: account_payable account_payable_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.account_payable
    ADD CONSTRAINT account_payable_pkey PRIMARY KEY (account_payable_id);


--
-- Name: account_payable_status account_payable_status_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.account_payable_status
    ADD CONSTRAINT account_payable_status_pkey PRIMARY KEY (status_id);


--
-- Name: account_payable account_payable_supply_order_id_key; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.account_payable
    ADD CONSTRAINT account_payable_supply_order_id_key UNIQUE (supply_order_id);


--
-- Name: goods_receipt_item goods_receipt_item_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.goods_receipt_item
    ADD CONSTRAINT goods_receipt_item_pkey PRIMARY KEY (goods_receipt_item_id);


--
-- Name: goods_receipt goods_receipt_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.goods_receipt
    ADD CONSTRAINT goods_receipt_pkey PRIMARY KEY (goods_receipt_id);


--
-- Name: supplier_branch supplier_branch_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supplier_branch
    ADD CONSTRAINT supplier_branch_pkey PRIMARY KEY (supplier_branch_id);


--
-- Name: supplier_branch supplier_branch_supplier_id_branch_id_key; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supplier_branch
    ADD CONSTRAINT supplier_branch_supplier_id_branch_id_key UNIQUE (supplier_id, branch_id);


--
-- Name: supplier_invoice_item supplier_invoice_item_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supplier_invoice_item
    ADD CONSTRAINT supplier_invoice_item_pkey PRIMARY KEY (supplier_invoice_item_id);


--
-- Name: supplier_invoice supplier_invoice_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supplier_invoice
    ADD CONSTRAINT supplier_invoice_pkey PRIMARY KEY (supplier_invoice_id);


--
-- Name: supplier supplier_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supplier
    ADD CONSTRAINT supplier_pkey PRIMARY KEY (supplier_id);


--
-- Name: supply_order_item supply_order_item_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_item
    ADD CONSTRAINT supply_order_item_pkey PRIMARY KEY (supply_order_item_id);


--
-- Name: supply_order_payment_alert_config supply_order_payment_alert_config_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_payment_alert_config
    ADD CONSTRAINT supply_order_payment_alert_config_pkey PRIMARY KEY (payment_alert_config_id);


--
-- Name: supply_order_payment_alert_config supply_order_payment_alert_config_tenant_id_key; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_payment_alert_config
    ADD CONSTRAINT supply_order_payment_alert_config_tenant_id_key UNIQUE (tenant_id);


--
-- Name: supply_order_payment_alert supply_order_payment_alert_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_payment_alert
    ADD CONSTRAINT supply_order_payment_alert_pkey PRIMARY KEY (payment_alert_id);


--
-- Name: supply_order_payment_alert_type supply_order_payment_alert_type_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_payment_alert_type
    ADD CONSTRAINT supply_order_payment_alert_type_pkey PRIMARY KEY (payment_alert_type_id);


--
-- Name: supply_order_payment supply_order_payment_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_payment
    ADD CONSTRAINT supply_order_payment_pkey PRIMARY KEY (payment_id);


--
-- Name: supply_order supply_order_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order
    ADD CONSTRAINT supply_order_pkey PRIMARY KEY (supply_order_id);


--
-- Name: supply_order_status supply_order_status_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_status
    ADD CONSTRAINT supply_order_status_pkey PRIMARY KEY (status_id);


--
-- Name: supply_order_tracking supply_order_tracking_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_tracking
    ADD CONSTRAINT supply_order_tracking_pkey PRIMARY KEY (supply_order_tracking_id);


--
-- Name: three_way_matching three_way_matching_pkey; Type: CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.three_way_matching
    ADD CONSTRAINT three_way_matching_pkey PRIMARY KEY (matching_id);


--
-- Name: idx_product_name_fts; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_product_name_fts ON ONLY core.product USING gin (product_name_tsv);


--
-- Name: idx_product_tenant_btree; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX idx_product_tenant_btree ON ONLY core.product USING btree (tenant_id);


--
-- Name: idx_product_tenant_sku; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX idx_product_tenant_sku ON ONLY core.product USING btree (tenant_id, sku);


--
-- Name: product_p0_product_name_tsv_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p0_product_name_tsv_idx ON core.product_p0 USING gin (product_name_tsv);


--
-- Name: product_p0_tenant_id_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p0_tenant_id_idx ON core.product_p0 USING btree (tenant_id);


--
-- Name: product_p0_tenant_id_sku_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX product_p0_tenant_id_sku_idx ON core.product_p0 USING btree (tenant_id, sku);


--
-- Name: product_p1_product_name_tsv_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p1_product_name_tsv_idx ON core.product_p1 USING gin (product_name_tsv);


--
-- Name: product_p1_tenant_id_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p1_tenant_id_idx ON core.product_p1 USING btree (tenant_id);


--
-- Name: product_p1_tenant_id_sku_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX product_p1_tenant_id_sku_idx ON core.product_p1 USING btree (tenant_id, sku);


--
-- Name: product_p2_product_name_tsv_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p2_product_name_tsv_idx ON core.product_p2 USING gin (product_name_tsv);


--
-- Name: product_p2_tenant_id_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p2_tenant_id_idx ON core.product_p2 USING btree (tenant_id);


--
-- Name: product_p2_tenant_id_sku_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX product_p2_tenant_id_sku_idx ON core.product_p2 USING btree (tenant_id, sku);


--
-- Name: product_p3_product_name_tsv_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p3_product_name_tsv_idx ON core.product_p3 USING gin (product_name_tsv);


--
-- Name: product_p3_tenant_id_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p3_tenant_id_idx ON core.product_p3 USING btree (tenant_id);


--
-- Name: product_p3_tenant_id_sku_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX product_p3_tenant_id_sku_idx ON core.product_p3 USING btree (tenant_id, sku);


--
-- Name: product_p4_product_name_tsv_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p4_product_name_tsv_idx ON core.product_p4 USING gin (product_name_tsv);


--
-- Name: product_p4_tenant_id_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p4_tenant_id_idx ON core.product_p4 USING btree (tenant_id);


--
-- Name: product_p4_tenant_id_sku_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX product_p4_tenant_id_sku_idx ON core.product_p4 USING btree (tenant_id, sku);


--
-- Name: product_p5_product_name_tsv_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p5_product_name_tsv_idx ON core.product_p5 USING gin (product_name_tsv);


--
-- Name: product_p5_tenant_id_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p5_tenant_id_idx ON core.product_p5 USING btree (tenant_id);


--
-- Name: product_p5_tenant_id_sku_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX product_p5_tenant_id_sku_idx ON core.product_p5 USING btree (tenant_id, sku);


--
-- Name: product_p6_product_name_tsv_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p6_product_name_tsv_idx ON core.product_p6 USING gin (product_name_tsv);


--
-- Name: product_p6_tenant_id_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p6_tenant_id_idx ON core.product_p6 USING btree (tenant_id);


--
-- Name: product_p6_tenant_id_sku_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX product_p6_tenant_id_sku_idx ON core.product_p6 USING btree (tenant_id, sku);


--
-- Name: product_p7_product_name_tsv_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p7_product_name_tsv_idx ON core.product_p7 USING gin (product_name_tsv);


--
-- Name: product_p7_tenant_id_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE INDEX product_p7_tenant_id_idx ON core.product_p7 USING btree (tenant_id);


--
-- Name: product_p7_tenant_id_sku_idx; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX product_p7_tenant_id_sku_idx ON core.product_p7 USING btree (tenant_id, sku);


--
-- Name: unique_attribute_name; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX unique_attribute_name ON core.global_attribute USING btree (lower((attribute_name)::text));


--
-- Name: unique_main_branch_per_tenant; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX unique_main_branch_per_tenant ON core.branch USING btree (tenant_id) WHERE (is_main_branch = true);


--
-- Name: unique_tenant_attribute_name; Type: INDEX; Schema: core; Owner: -
--

CREATE UNIQUE INDEX unique_tenant_attribute_name ON core.tenant_attribute USING btree (tenant_id, lower((attribute_name)::text));


--
-- Name: idx_bill_sale_id; Type: INDEX; Schema: pos_module; Owner: -
--

CREATE INDEX idx_bill_sale_id ON pos_module.bill USING btree (sale_id);


--
-- Name: idx_return_product_transaction_id; Type: INDEX; Schema: pos_module; Owner: -
--

CREATE INDEX idx_return_product_transaction_id ON pos_module.return_product USING btree (return_transaction_id);


--
-- Name: idx_return_transaction_bill_id; Type: INDEX; Schema: pos_module; Owner: -
--

CREATE INDEX idx_return_transaction_bill_id ON pos_module.return_transaction USING btree (bill_id);


--
-- Name: idx_return_transaction_date; Type: INDEX; Schema: pos_module; Owner: -
--

CREATE INDEX idx_return_transaction_date ON pos_module.return_transaction USING btree (return_date);


--
-- Name: idx_sale_branch_id; Type: INDEX; Schema: pos_module; Owner: -
--

CREATE INDEX idx_sale_branch_id ON pos_module.sale USING btree (branch_id);


--
-- Name: idx_sale_item_product_id; Type: INDEX; Schema: pos_module; Owner: -
--

CREATE INDEX idx_sale_item_product_id ON pos_module.sale_item USING btree (product_id);


--
-- Name: idx_sale_item_sale_id; Type: INDEX; Schema: pos_module; Owner: -
--

CREATE INDEX idx_sale_item_sale_id ON pos_module.sale_item USING btree (sale_id);


--
-- Name: idx_sale_item_tenant_product; Type: INDEX; Schema: pos_module; Owner: -
--

CREATE INDEX idx_sale_item_tenant_product ON pos_module.sale_item USING btree (tenant_id, product_id);


--
-- Name: idx_sale_sale_date; Type: INDEX; Schema: pos_module; Owner: -
--

CREATE INDEX idx_sale_sale_date ON pos_module.sale USING btree (sale_date);


--
-- Name: ux_supplier_name; Type: INDEX; Schema: supplies_module; Owner: -
--

CREATE UNIQUE INDEX ux_supplier_name ON supplies_module.supplier USING btree (supplier_name);


--
-- Name: product_p0_pkey; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.product_pkey ATTACH PARTITION core.product_p0_pkey;


--
-- Name: product_p0_product_name_tsv_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_name_fts ATTACH PARTITION core.product_p0_product_name_tsv_idx;


--
-- Name: product_p0_tenant_id_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_btree ATTACH PARTITION core.product_p0_tenant_id_idx;


--
-- Name: product_p0_tenant_id_sku_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_sku ATTACH PARTITION core.product_p0_tenant_id_sku_idx;


--
-- Name: product_p1_pkey; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.product_pkey ATTACH PARTITION core.product_p1_pkey;


--
-- Name: product_p1_product_name_tsv_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_name_fts ATTACH PARTITION core.product_p1_product_name_tsv_idx;


--
-- Name: product_p1_tenant_id_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_btree ATTACH PARTITION core.product_p1_tenant_id_idx;


--
-- Name: product_p1_tenant_id_sku_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_sku ATTACH PARTITION core.product_p1_tenant_id_sku_idx;


--
-- Name: product_p2_pkey; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.product_pkey ATTACH PARTITION core.product_p2_pkey;


--
-- Name: product_p2_product_name_tsv_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_name_fts ATTACH PARTITION core.product_p2_product_name_tsv_idx;


--
-- Name: product_p2_tenant_id_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_btree ATTACH PARTITION core.product_p2_tenant_id_idx;


--
-- Name: product_p2_tenant_id_sku_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_sku ATTACH PARTITION core.product_p2_tenant_id_sku_idx;


--
-- Name: product_p3_pkey; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.product_pkey ATTACH PARTITION core.product_p3_pkey;


--
-- Name: product_p3_product_name_tsv_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_name_fts ATTACH PARTITION core.product_p3_product_name_tsv_idx;


--
-- Name: product_p3_tenant_id_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_btree ATTACH PARTITION core.product_p3_tenant_id_idx;


--
-- Name: product_p3_tenant_id_sku_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_sku ATTACH PARTITION core.product_p3_tenant_id_sku_idx;


--
-- Name: product_p4_pkey; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.product_pkey ATTACH PARTITION core.product_p4_pkey;


--
-- Name: product_p4_product_name_tsv_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_name_fts ATTACH PARTITION core.product_p4_product_name_tsv_idx;


--
-- Name: product_p4_tenant_id_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_btree ATTACH PARTITION core.product_p4_tenant_id_idx;


--
-- Name: product_p4_tenant_id_sku_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_sku ATTACH PARTITION core.product_p4_tenant_id_sku_idx;


--
-- Name: product_p5_pkey; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.product_pkey ATTACH PARTITION core.product_p5_pkey;


--
-- Name: product_p5_product_name_tsv_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_name_fts ATTACH PARTITION core.product_p5_product_name_tsv_idx;


--
-- Name: product_p5_tenant_id_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_btree ATTACH PARTITION core.product_p5_tenant_id_idx;


--
-- Name: product_p5_tenant_id_sku_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_sku ATTACH PARTITION core.product_p5_tenant_id_sku_idx;


--
-- Name: product_p6_pkey; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.product_pkey ATTACH PARTITION core.product_p6_pkey;


--
-- Name: product_p6_product_name_tsv_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_name_fts ATTACH PARTITION core.product_p6_product_name_tsv_idx;


--
-- Name: product_p6_tenant_id_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_btree ATTACH PARTITION core.product_p6_tenant_id_idx;


--
-- Name: product_p6_tenant_id_sku_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_sku ATTACH PARTITION core.product_p6_tenant_id_sku_idx;


--
-- Name: product_p7_pkey; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.product_pkey ATTACH PARTITION core.product_p7_pkey;


--
-- Name: product_p7_product_name_tsv_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_name_fts ATTACH PARTITION core.product_p7_product_name_tsv_idx;


--
-- Name: product_p7_tenant_id_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_btree ATTACH PARTITION core.product_p7_tenant_id_idx;


--
-- Name: product_p7_tenant_id_sku_idx; Type: INDEX ATTACH; Schema: core; Owner: -
--

ALTER INDEX core.idx_product_tenant_sku ATTACH PARTITION core.product_p7_tenant_id_sku_idx;


--
-- Name: return_product trigger_increase_stock; Type: TRIGGER; Schema: pos_module; Owner: -
--

CREATE TRIGGER trigger_increase_stock AFTER INSERT ON pos_module.return_product FOR EACH ROW EXECUTE FUNCTION inventory_module.increase_stock_on_return();


--
-- Name: sale trigger_reduce_stock; Type: TRIGGER; Schema: pos_module; Owner: -
--

CREATE TRIGGER trigger_reduce_stock AFTER INSERT ON pos_module.sale FOR EACH ROW EXECUTE FUNCTION inventory_module.reduce_stock_on_sale();


--
-- Name: branch branch_tenant_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.branch
    ADD CONSTRAINT branch_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES core.tenant(tenant_id) ON DELETE CASCADE;


--
-- Name: customer_segment_margin customer_segment_margin_customer_segment_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_segment_margin
    ADD CONSTRAINT customer_segment_margin_customer_segment_id_fkey FOREIGN KEY (customer_segment_id) REFERENCES core.customer_segment(customer_segment_id) ON DELETE CASCADE;


--
-- Name: customer_segment_margin customer_segment_margin_customer_segment_margin_type_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_segment_margin
    ADD CONSTRAINT customer_segment_margin_customer_segment_margin_type_id_fkey FOREIGN KEY (customer_segment_margin_type_id) REFERENCES core.customer_segment_margin_type(customer_segment_margin_type_id) ON DELETE SET NULL;


--
-- Name: customer_segment_margin customer_segment_margin_tenant_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.customer_segment_margin
    ADD CONSTRAINT customer_segment_margin_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES core.tenant(tenant_id) ON DELETE CASCADE;


--
-- Name: product_attribute product_attribute_tenant_attribute_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_attribute
    ADD CONSTRAINT product_attribute_tenant_attribute_id_fkey FOREIGN KEY (tenant_attribute_id) REFERENCES core.tenant_attribute(tenant_attribute_id) ON DELETE CASCADE;


--
-- Name: product_attribute product_attribute_tenant_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_attribute
    ADD CONSTRAINT product_attribute_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES core.tenant(tenant_id) ON DELETE CASCADE;


--
-- Name: product_attribute product_attribute_tenant_id_product_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.product_attribute
    ADD CONSTRAINT product_attribute_tenant_id_product_id_fkey FOREIGN KEY (tenant_id, product_id) REFERENCES core.product(tenant_id, product_id) ON DELETE CASCADE;


--
-- Name: product product_product_category_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE core.product
    ADD CONSTRAINT product_product_category_id_fkey FOREIGN KEY (product_category_id) REFERENCES core.product_category(product_category_id) ON DELETE SET NULL;


--
-- Name: product product_tenant_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE core.product
    ADD CONSTRAINT product_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES core.tenant(tenant_id) ON DELETE CASCADE;


--
-- Name: subscription subscription_subscription_type_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.subscription
    ADD CONSTRAINT subscription_subscription_type_id_fkey FOREIGN KEY (subscription_type_id) REFERENCES core.subscription_type(subscription_type_id) ON DELETE SET NULL;


--
-- Name: subscription subscription_tenant_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.subscription
    ADD CONSTRAINT subscription_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES core.tenant(tenant_id) ON DELETE CASCADE;


--
-- Name: subscription subscription_tenant_payment_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.subscription
    ADD CONSTRAINT subscription_tenant_payment_id_fkey FOREIGN KEY (tenant_payment_id) REFERENCES core.tenant_payment(tenant_payment_id) ON DELETE SET NULL;


--
-- Name: tax_rate tax_rate_region_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tax_rate
    ADD CONSTRAINT tax_rate_region_id_fkey FOREIGN KEY (region_id) REFERENCES core.region(region_id) ON DELETE SET NULL;


--
-- Name: tenant_attribute tenant_attribute_global_attribute_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant_attribute
    ADD CONSTRAINT tenant_attribute_global_attribute_id_fkey FOREIGN KEY (global_attribute_id) REFERENCES core.global_attribute(global_attribute_id) ON DELETE SET NULL;


--
-- Name: tenant_attribute tenant_attribute_tenant_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant_attribute
    ADD CONSTRAINT tenant_attribute_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES core.tenant(tenant_id) ON DELETE CASCADE;


--
-- Name: tenant_customer tenant_customer_customer_segment_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant_customer
    ADD CONSTRAINT tenant_customer_customer_segment_id_fkey FOREIGN KEY (customer_segment_id) REFERENCES core.customer_segment(customer_segment_id) ON DELETE SET NULL;


--
-- Name: tenant_customer tenant_customer_document_type_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant_customer
    ADD CONSTRAINT tenant_customer_document_type_id_fkey FOREIGN KEY (document_type_id) REFERENCES core.document_type(document_type_id) ON DELETE SET NULL;


--
-- Name: tenant_customer tenant_customer_tenant_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant_customer
    ADD CONSTRAINT tenant_customer_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES core.tenant(tenant_id) ON DELETE CASCADE;


--
-- Name: tenant_payment tenant_payment_payment_method_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant_payment
    ADD CONSTRAINT tenant_payment_payment_method_id_fkey FOREIGN KEY (payment_method_id) REFERENCES core.payment_method(payment_method_id) ON DELETE SET NULL;


--
-- Name: tenant_payment tenant_payment_tenant_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant_payment
    ADD CONSTRAINT tenant_payment_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES core.tenant(tenant_id) ON DELETE CASCADE;


--
-- Name: tenant tenant_region_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.tenant
    ADD CONSTRAINT tenant_region_id_fkey FOREIGN KEY (region_id) REFERENCES core.region(region_id) ON DELETE SET NULL;


--
-- Name: users users_role_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.users
    ADD CONSTRAINT users_role_id_fkey FOREIGN KEY (role_id) REFERENCES core.role(role_id) ON DELETE SET NULL;


--
-- Name: users users_tenant_id_fkey; Type: FK CONSTRAINT; Schema: core; Owner: -
--

ALTER TABLE ONLY core.users
    ADD CONSTRAINT users_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES core.tenant(tenant_id) ON DELETE CASCADE;


--
-- Name: inventory_movement inventory_movement_inventory_movement_type_id_fkey; Type: FK CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.inventory_log
    ADD CONSTRAINT inventory_log_inventory_movement_type_id_fkey FOREIGN KEY (inventory_movement_type_id) REFERENCES inventory_module.inventory_movement_type(inventory_movement_type_id) ON DELETE CASCADE;


--
-- Name: inventory_movement inventory_movement_supply_order_id_fkey; Type: FK CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.inventory_log
    ADD CONSTRAINT inventory_log_supply_order_id_fkey FOREIGN KEY (supply_order_id) REFERENCES supplies_module.supply_order(supply_order_id) ON DELETE SET NULL;


--
-- Name: inventory inventory_tenant_id_product_id_fkey; Type: FK CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.inventory
    ADD CONSTRAINT inventory_tenant_id_product_id_fkey FOREIGN KEY (tenant_id, product_id) REFERENCES core.product(tenant_id, product_id) ON DELETE CASCADE;


--
-- Name: inventory_transfer inventory_transfer_from_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.inventory_transfer
    ADD CONSTRAINT inventory_transfer_from_warehouse_id_fkey FOREIGN KEY (from_warehouse_id) REFERENCES inventory_module.warehouse(warehouse_id) ON DELETE CASCADE;


--
-- Name: inventory_transfer_product inventory_transfer_product_inventory_transfer_id_fkey; Type: FK CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.inventory_transfer_product
    ADD CONSTRAINT inventory_transfer_product_inventory_transfer_id_fkey FOREIGN KEY (inventory_transfer_id) REFERENCES inventory_module.inventory_transfer(inventory_transfer_id) ON DELETE CASCADE;


--
-- Name: inventory_transfer_product inventory_transfer_product_tenant_id_product_id_fkey; Type: FK CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.inventory_transfer_product
    ADD CONSTRAINT inventory_transfer_product_tenant_id_product_id_fkey FOREIGN KEY (tenant_id, product_id) REFERENCES core.product(tenant_id, product_id) ON DELETE CASCADE;


--
-- Name: inventory_transfer inventory_transfer_to_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.inventory_transfer
    ADD CONSTRAINT inventory_transfer_to_warehouse_id_fkey FOREIGN KEY (to_warehouse_id) REFERENCES inventory_module.warehouse(warehouse_id) ON DELETE CASCADE;


--
-- Name: inventory inventory_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.inventory
    ADD CONSTRAINT inventory_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES inventory_module.warehouse(warehouse_id) ON DELETE CASCADE;


--
-- Name: warehouse warehouse_branch_id_fkey; Type: FK CONSTRAINT; Schema: inventory_module; Owner: -
--

ALTER TABLE ONLY inventory_module.warehouse
    ADD CONSTRAINT warehouse_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES core.branch(branch_id) ON DELETE CASCADE;


--
-- Name: bill bill_currency_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.bill
    ADD CONSTRAINT bill_currency_id_fkey FOREIGN KEY (currency_id) REFERENCES core.currency(currency_id) ON DELETE SET NULL;


--
-- Name: bill_payment bill_payment_bill_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.bill_payment
    ADD CONSTRAINT bill_payment_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES pos_module.bill(bill_id) ON DELETE CASCADE;


--
-- Name: bill_payment bill_payment_customer_payment_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.bill_payment
    ADD CONSTRAINT bill_payment_customer_payment_id_fkey FOREIGN KEY (customer_payment_id) REFERENCES pos_module.customer_payment(customer_payment_id) ON DELETE CASCADE;


--
-- Name: bill bill_sale_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.bill
    ADD CONSTRAINT bill_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES pos_module.sale(sale_id) ON DELETE CASCADE;


--
-- Name: bill bill_tenant_customer_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.bill
    ADD CONSTRAINT bill_tenant_customer_id_fkey FOREIGN KEY (tenant_customer_id) REFERENCES core.tenant_customer(tenant_customer_id) ON DELETE SET NULL;


--
-- Name: cash_register cash_register_branch_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.cash_register
    ADD CONSTRAINT cash_register_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES core.branch(branch_id) ON DELETE CASCADE;


--
-- Name: cash_register_sale cash_register_sale_cash_register_session_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.cash_register_sale
    ADD CONSTRAINT cash_register_sale_cash_register_session_id_fkey FOREIGN KEY (cash_register_session_id) REFERENCES pos_module.cash_register_session(cash_register_session_id) ON DELETE CASCADE;


--
-- Name: cash_register_sale cash_register_sale_sale_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.cash_register_sale
    ADD CONSTRAINT cash_register_sale_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES pos_module.sale(sale_id) ON DELETE CASCADE;


--
-- Name: cash_register_session cash_register_session_cash_register_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.cash_register_session
    ADD CONSTRAINT cash_register_session_cash_register_id_fkey FOREIGN KEY (cash_register_id) REFERENCES pos_module.cash_register(cash_register_id) ON DELETE CASCADE;


--
-- Name: cash_register_session cash_register_session_user_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.cash_register_session
    ADD CONSTRAINT cash_register_session_user_id_fkey FOREIGN KEY (user_id) REFERENCES core.users(user_id) ON DELETE SET NULL;


--
-- Name: customer_payment customer_payment_currency_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.customer_payment
    ADD CONSTRAINT customer_payment_currency_id_fkey FOREIGN KEY (currency_id) REFERENCES core.currency(currency_id) ON DELETE SET NULL;


--
-- Name: customer_payment customer_payment_payment_method_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.customer_payment
    ADD CONSTRAINT customer_payment_payment_method_id_fkey FOREIGN KEY (payment_method_id) REFERENCES core.payment_method(payment_method_id) ON DELETE SET NULL;


--
-- Name: customer_payment customer_payment_sale_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.customer_payment
    ADD CONSTRAINT customer_payment_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES pos_module.sale(sale_id) ON DELETE CASCADE;


--
-- Name: customer_payment customer_payment_tenant_customer_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.customer_payment
    ADD CONSTRAINT customer_payment_tenant_customer_id_fkey FOREIGN KEY (tenant_customer_id) REFERENCES core.tenant_customer(tenant_customer_id) ON DELETE CASCADE;


--
-- Name: loyalty_program loyalty_program_tenant_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.loyalty_program
    ADD CONSTRAINT loyalty_program_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES core.tenant(tenant_id) ON DELETE CASCADE;


--
-- Name: promotion promotion_customer_segment_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.promotion
    ADD CONSTRAINT promotion_customer_segment_id_fkey FOREIGN KEY (customer_segment_id) REFERENCES core.customer_segment(customer_segment_id) ON DELETE SET NULL;


--
-- Name: promotion promotion_promotion_type_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.promotion
    ADD CONSTRAINT promotion_promotion_type_id_fkey FOREIGN KEY (promotion_type_id) REFERENCES pos_module.promotion_type(promotion_type_id) ON DELETE SET NULL;


--
-- Name: promotion_rule promotion_rule_promotion_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.promotion_rule
    ADD CONSTRAINT promotion_rule_promotion_id_fkey FOREIGN KEY (promotion_id) REFERENCES pos_module.promotion(promotion_id) ON DELETE CASCADE;


--
-- Name: promotion promotion_tenant_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.promotion
    ADD CONSTRAINT promotion_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES core.tenant(tenant_id) ON DELETE CASCADE;


--
-- Name: return_product return_product_return_transaction_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.return_product
    ADD CONSTRAINT return_product_return_transaction_id_fkey FOREIGN KEY (return_transaction_id) REFERENCES pos_module.return_transaction(return_transaction_id) ON DELETE CASCADE;


--
-- Name: return_product return_product_sale_item_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.return_product
    ADD CONSTRAINT return_product_sale_item_id_fkey FOREIGN KEY (sale_item_id) REFERENCES pos_module.sale_item(sale_item_id) ON DELETE CASCADE;


--
-- Name: return_transaction return_transaction_bill_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.return_transaction
    ADD CONSTRAINT return_transaction_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES pos_module.bill(bill_id) ON DELETE CASCADE;


--
-- Name: return_transaction return_transaction_refund_method_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.return_transaction
    ADD CONSTRAINT return_transaction_refund_method_fkey FOREIGN KEY (refund_method) REFERENCES core.payment_method(payment_method_id) ON DELETE SET NULL;


--
-- Name: return_transaction return_transaction_return_status_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.return_transaction
    ADD CONSTRAINT return_transaction_return_status_id_fkey FOREIGN KEY (return_status_id) REFERENCES pos_module.return_status(return_status_id) ON DELETE SET NULL;


--
-- Name: return_transaction return_transaction_tenant_customer_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.return_transaction
    ADD CONSTRAINT return_transaction_tenant_customer_id_fkey FOREIGN KEY (tenant_customer_id) REFERENCES core.tenant_customer(tenant_customer_id) ON DELETE SET NULL;


--
-- Name: sale sale_branch_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.sale
    ADD CONSTRAINT sale_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES core.branch(branch_id) ON DELETE CASCADE;


--
-- Name: sale sale_currency_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.sale
    ADD CONSTRAINT sale_currency_id_fkey FOREIGN KEY (currency_id) REFERENCES core.currency(currency_id) ON DELETE SET NULL;


--
-- Name: sale_item sale_item_sale_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.sale_item
    ADD CONSTRAINT sale_item_sale_id_fkey FOREIGN KEY (sale_id) REFERENCES pos_module.sale(sale_id) ON DELETE CASCADE;


--
-- Name: sale_item sale_item_tenant_id_product_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.sale_item
    ADD CONSTRAINT sale_item_tenant_id_product_id_fkey FOREIGN KEY (tenant_id, product_id) REFERENCES core.product(tenant_id, product_id) ON DELETE RESTRICT;


--
-- Name: score_transaction score_transaction_bill_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.score_transaction
    ADD CONSTRAINT score_transaction_bill_id_fkey FOREIGN KEY (bill_id) REFERENCES pos_module.bill(bill_id) ON DELETE SET NULL;


--
-- Name: score_transaction score_transaction_tenant_customer_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.score_transaction
    ADD CONSTRAINT score_transaction_tenant_customer_id_fkey FOREIGN KEY (tenant_customer_id) REFERENCES core.tenant_customer(tenant_customer_id) ON DELETE CASCADE;


--
-- Name: score_transaction score_transaction_tenant_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.score_transaction
    ADD CONSTRAINT score_transaction_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES core.tenant(tenant_id) ON DELETE CASCADE;


--
-- Name: score_transaction score_transaction_transaction_type_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.score_transaction
    ADD CONSTRAINT score_transaction_transaction_type_id_fkey FOREIGN KEY (transaction_type_id) REFERENCES pos_module.score_transaction_type(score_transaction_type_id) ON DELETE SET NULL;


--
-- Name: tenant_customer_score tenant_customer_score_tenant_customer_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.tenant_customer_score
    ADD CONSTRAINT tenant_customer_score_tenant_customer_id_fkey FOREIGN KEY (tenant_customer_id) REFERENCES core.tenant_customer(tenant_customer_id) ON DELETE CASCADE;


--
-- Name: tenant_customer_score tenant_customer_score_tenant_id_fkey; Type: FK CONSTRAINT; Schema: pos_module; Owner: -
--

ALTER TABLE ONLY pos_module.tenant_customer_score
    ADD CONSTRAINT tenant_customer_score_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES core.tenant(tenant_id) ON DELETE CASCADE;


--
-- Name: account_payable account_payable_account_status_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.account_payable
    ADD CONSTRAINT account_payable_account_status_fkey FOREIGN KEY (account_status) REFERENCES supplies_module.account_payable_status(status_id);


--
-- Name: account_payable account_payable_supply_order_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.account_payable
    ADD CONSTRAINT account_payable_supply_order_id_fkey FOREIGN KEY (supply_order_id) REFERENCES supplies_module.supply_order(supply_order_id) ON DELETE CASCADE;


--
-- Name: goods_receipt_item goods_receipt_item_goods_receipt_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.goods_receipt_item
    ADD CONSTRAINT goods_receipt_item_goods_receipt_id_fkey FOREIGN KEY (goods_receipt_id) REFERENCES supplies_module.goods_receipt(goods_receipt_id) ON DELETE CASCADE;


--
-- Name: goods_receipt_item goods_receipt_item_tenant_id_product_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.goods_receipt_item
    ADD CONSTRAINT goods_receipt_item_tenant_id_product_id_fkey FOREIGN KEY (tenant_id, product_id) REFERENCES core.product(tenant_id, product_id) ON DELETE CASCADE;


--
-- Name: goods_receipt goods_receipt_supply_order_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.goods_receipt
    ADD CONSTRAINT goods_receipt_supply_order_id_fkey FOREIGN KEY (supply_order_id) REFERENCES supplies_module.supply_order(supply_order_id) ON DELETE CASCADE;


--
-- Name: supplier_branch supplier_branch_branch_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supplier_branch
    ADD CONSTRAINT supplier_branch_branch_id_fkey FOREIGN KEY (branch_id) REFERENCES core.branch(branch_id) ON DELETE CASCADE;


--
-- Name: supplier_branch supplier_branch_supplier_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supplier_branch
    ADD CONSTRAINT supplier_branch_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES supplies_module.supplier(supplier_id) ON DELETE CASCADE;


--
-- Name: supplier_invoice_item supplier_invoice_item_supplier_invoice_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supplier_invoice_item
    ADD CONSTRAINT supplier_invoice_item_supplier_invoice_id_fkey FOREIGN KEY (supplier_invoice_id) REFERENCES supplies_module.supplier_invoice(supplier_invoice_id) ON DELETE CASCADE;


--
-- Name: supplier_invoice_item supplier_invoice_item_tenant_id_product_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supplier_invoice_item
    ADD CONSTRAINT supplier_invoice_item_tenant_id_product_id_fkey FOREIGN KEY (tenant_id, product_id) REFERENCES core.product(tenant_id, product_id) ON DELETE CASCADE;


--
-- Name: supplier_invoice supplier_invoice_supply_order_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supplier_invoice
    ADD CONSTRAINT supplier_invoice_supply_order_id_fkey FOREIGN KEY (supply_order_id) REFERENCES supplies_module.supply_order(supply_order_id) ON DELETE CASCADE;


--
-- Name: supply_order_item supply_order_item_supply_order_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_item
    ADD CONSTRAINT supply_order_item_supply_order_id_fkey FOREIGN KEY (supply_order_id) REFERENCES supplies_module.supply_order(supply_order_id) ON DELETE CASCADE;


--
-- Name: supply_order_item supply_order_item_tenant_id_product_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_item
    ADD CONSTRAINT supply_order_item_tenant_id_product_id_fkey FOREIGN KEY (tenant_id, product_id) REFERENCES core.product(tenant_id, product_id) ON DELETE CASCADE;


--
-- Name: supply_order_payment supply_order_payment_account_payable_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_payment
    ADD CONSTRAINT supply_order_payment_account_payable_id_fkey FOREIGN KEY (account_payable_id) REFERENCES supplies_module.account_payable(account_payable_id) ON DELETE CASCADE;


--
-- Name: supply_order_payment_alert supply_order_payment_alert_account_payable_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_payment_alert
    ADD CONSTRAINT supply_order_payment_alert_account_payable_id_fkey FOREIGN KEY (account_payable_id) REFERENCES supplies_module.account_payable(account_payable_id) ON DELETE CASCADE;


--
-- Name: supply_order_payment_alert_config supply_order_payment_alert_config_tenant_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_payment_alert_config
    ADD CONSTRAINT supply_order_payment_alert_config_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES core.tenant(tenant_id) ON DELETE CASCADE;


--
-- Name: supply_order_payment_alert supply_order_payment_alert_payment_alert_type_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_payment_alert
    ADD CONSTRAINT supply_order_payment_alert_payment_alert_type_id_fkey FOREIGN KEY (payment_alert_type_id) REFERENCES supplies_module.supply_order_payment_alert_type(payment_alert_type_id);


--
-- Name: supply_order_payment supply_order_payment_payment_method_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_payment
    ADD CONSTRAINT supply_order_payment_payment_method_id_fkey FOREIGN KEY (payment_method_id) REFERENCES core.payment_method(payment_method_id) ON DELETE CASCADE;


--
-- Name: supply_order_payment supply_order_payment_tenant_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_payment
    ADD CONSTRAINT supply_order_payment_tenant_id_fkey FOREIGN KEY (tenant_id) REFERENCES core.tenant(tenant_id) ON DELETE CASCADE;


--
-- Name: supply_order supply_order_supplier_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order
    ADD CONSTRAINT supply_order_supplier_id_fkey FOREIGN KEY (supplier_id) REFERENCES supplies_module.supplier(supplier_id) ON DELETE CASCADE;


--
-- Name: supply_order supply_order_supply_order_status_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order
    ADD CONSTRAINT supply_order_supply_order_status_id_fkey FOREIGN KEY (supply_order_status_id) REFERENCES supplies_module.supply_order_status(status_id);


--
-- Name: supply_order_tracking supply_order_tracking_new_status_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_tracking
    ADD CONSTRAINT supply_order_tracking_new_status_id_fkey FOREIGN KEY (new_status_id) REFERENCES supplies_module.supply_order_status(status_id);


--
-- Name: supply_order_tracking supply_order_tracking_previous_status_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_tracking
    ADD CONSTRAINT supply_order_tracking_previous_status_id_fkey FOREIGN KEY (previous_status_id) REFERENCES supplies_module.supply_order_status(status_id);


--
-- Name: supply_order_tracking supply_order_tracking_supply_order_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order_tracking
    ADD CONSTRAINT supply_order_tracking_supply_order_id_fkey FOREIGN KEY (supply_order_id) REFERENCES supplies_module.supply_order(supply_order_id) ON DELETE CASCADE;


--
-- Name: supply_order supply_order_warehouse_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.supply_order
    ADD CONSTRAINT supply_order_warehouse_id_fkey FOREIGN KEY (warehouse_id) REFERENCES inventory_module.warehouse(warehouse_id) ON DELETE CASCADE;


--
-- Name: three_way_matching three_way_matching_goods_receipt_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.three_way_matching
    ADD CONSTRAINT three_way_matching_goods_receipt_id_fkey FOREIGN KEY (goods_receipt_id) REFERENCES supplies_module.goods_receipt(goods_receipt_id) ON DELETE CASCADE;


--
-- Name: three_way_matching three_way_matching_supplier_invoice_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.three_way_matching
    ADD CONSTRAINT three_way_matching_supplier_invoice_id_fkey FOREIGN KEY (supplier_invoice_id) REFERENCES supplies_module.supplier_invoice(supplier_invoice_id) ON DELETE CASCADE;


--
-- Name: three_way_matching three_way_matching_supply_order_id_fkey; Type: FK CONSTRAINT; Schema: supplies_module; Owner: -
--

ALTER TABLE ONLY supplies_module.three_way_matching
    ADD CONSTRAINT three_way_matching_supply_order_id_fkey FOREIGN KEY (supply_order_id) REFERENCES supplies_module.supply_order(supply_order_id) ON DELETE CASCADE;


--
-- PostgreSQL database dump complete
--

\unrestrict RIQTKbTf60aFF66laZnokAtfcUjOBL8VxchYiWzopiO4vj0kge4655Dfe02pvfc

