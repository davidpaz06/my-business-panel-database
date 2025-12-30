CREATE OR REPLACE FUNCTION reduce_stock_on_sale()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE inventory_module.inventory
    SET stock = stock - NEW.quantity_sold
    WHERE inventory_id = NEW.inventory_id;

    -- Check if stock went negative
    IF (SELECT stock FROM inventory_module.inventory WHERE inventory_id = NEW.inventory_id) < 0 THEN
        RAISE EXCEPTION 'Not enough stock for product ID %', NEW.product_id;
    END IF;

    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_reduce_stock
    AFTER INSERT ON pos_module.sales
FOR EACH ROW
    EXECUTE FUNCTION reduce_stock_on_sale();

CREATE OR REPLACE FUNCTION increase_stock_on_return()
RETURNS TRIGGER AS $$
BEGIN
    UPDATE products
    SET stock = stock + NEW.quantity_returned
    WHERE id = NEW.product_id;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trigger_increase_stock
    AFTER INSERT ON pos_module.return_product
FOR EACH ROW
    EXECUTE FUNCTION increase_stock_on_return();

CREATE OR REPLACE FUNCTION count_warehouse_inventory_products()
RETURNS TABLE(warehouse_id uuid, product_name varchar, product_count bigint) AS $$
BEGIN
    RETURN QUERY
    SELECT w.warehouse_id, p.product_name AS product_name, COUNT(i.product_id) AS product_count
    FROM inventory_module.warehouse w
    LEFT JOIN inventory_module.inventory i ON w.warehouse_id = i.warehouse_id
    INNER JOIN core.product p ON i.product_id = p.product_id AND i.tenant_id = p.tenant_id
    GROUP BY w.warehouse_id, p.product_name;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION log_inventory_movement()
RETURNS TRIGGER AS $$
BEGIN
    INSERT INTO inventory_module.inventory_log (inventory_log_type_id, supply_order_id)
    VALUES (NEW.movement_type_id, NEW.supply_order_id);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;
CREATE TRIGGER trigger_log_inventory_movement
    AFTER INSERT ON supplies_module.supply_order_product
FOR EACH ROW
    EXECUTE FUNCTION log_inventory_movement();