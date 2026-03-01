-- индекс для ускорения фильтрации заказов по статусу и дате
CREATE INDEX idx_orders_status_date ON orders(status, date_created);

-- покрывающий индекс для оптимизации JOIN и агрегации
CREATE INDEX idx_order_product_order_id_quantity ON order_product(order_id) INCLUDE (quantity);