-- перенос цен в основную таблицу и установка PK
ALTER TABLE product ADD COLUMN price double precision;
ALTER TABLE product ADD PRIMARY KEY (id);

-- перенос даты в таблицу заказов и установка PK
ALTER TABLE orders ADD COLUMN date_created date DEFAULT CURRENT_DATE;
ALTER TABLE orders ADD PRIMARY KEY (id);

-- установка связей между заказами и продуктами
ALTER TABLE order_product 
    ADD CONSTRAINT fk_order_product_order FOREIGN KEY (order_id) REFERENCES orders(id),
    ADD CONSTRAINT fk_order_product_product FOREIGN KEY (product_id) REFERENCES product(id);

-- удаление таблиц
DROP TABLE product_info;
DROP TABLE orders_date;