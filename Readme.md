# DBOps Project

## Настройка окружения и прав доступа

Для работы с базой данных `store` был создан отдельный пользователь. 
SQL-запросы, использованные для инициализации:

```sql
CREATE DATABASE store;
CREATE USER flyway_user WITH PASSWORD <pass>;
GRANT ALL PRIVILEGES ON DATABASE store TO flyway_user;
\c store
GRANT ALL ON SCHEMA public TO flyway_user;
```

## Аналитический запрос

Для включения таймера выполнения:

```sql
\timing
```

Запрос для получения данных о количестве проданных сосисок (статус `shipped`) за последнюю неделю:

```sql
SELECT o.date_created, SUM(op.quantity)
FROM orders AS o
JOIN order_product AS op ON o.id = op.order_id
WHERE o.status = 'shipped' 
  AND o.date_created > NOW() - INTERVAL '7 DAY'
GROUP BY o.date_created;
```

## Анализ

### 1: Контрольное выполнение
Начальное время выполнения запроса составило более 8.7 секунд. 
Система выполняла параллельное последовательное сканирование (Parallel Seq Scan) обеих таблиц.

**Результат замера:**
`Time: 8783.539 ms`

**План выполнения (фрагмент):**
```text
 Finalize GroupAggregate  (cost=266042.42..266065.47 rows=91 width=12) (actual time=10086.976..10112.796 rows=7 loops=1)
   Group Key: o.date_created
   ->  Gather Merge  (cost=266042.42..266063.65 rows=182 width=12) (actual time=10086.937..10112.749 rows=21 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         ->  Sort  (cost=265042.39..265042.62 rows=91 width=12) (actual time=9985.538..9985.543 rows=7 loops=3)
               Sort Key: o.date_created
               Sort Method: quicksort  Memory: 25kB
               Worker 0:  Sort Method: quicksort  Memory: 25kB
               Worker 1:  Sort Method: quicksort  Memory: 25kB
               ->  Partial HashAggregate  (cost=265038.52..265039.43 rows=91 width=12) (actual time=9985.459..9985.468 rows=7 loops=3)
                     Group Key: o.date_created
                     Batches: 1  Memory Usage: 24kB
                     Worker 0:  Batches: 1  Memory Usage: 24kB
                     Worker 1:  Batches: 1  Memory Usage: 24kB
                     ->  Parallel Hash Join  (cost=148249.75..264549.52 rows=97801 width=8) (actual time=4676.854..9901.674 rows=82187 loops=3)
                           Hash Cond: (op.order_id = o.id)
                           ->  Parallel Seq Scan on order_product op  (cost=0.00..105362.15 rows=4166715 width=12) (actual time=0.051..2409.568 rows=3333333 loops=3)
                           ->  Parallel Hash  (cost=147027.26..147027.26 rows=97799 width=12) (actual time=4673.624..4673.624 rows=82187 loops=3)
                                 Buckets: 262144  Batches: 1  Memory Usage: 13664kB
                                 ->  Parallel Seq Scan on orders o  (cost=0.00..147027.26 rows=97799 width=12) (actual time=48.160..4536.143 rows=82187 loops=3)
                                       Filter: (((status)::text = 'shipped'::text) AND (date_created > (now() - '7 days'::interval)))
                                       Rows Removed by Filter: 3251147
 Planning Time: 4.149 ms
 JIT:
   Functions: 54
   Options: Inlining false, Optimization false, Expressions true, Deforming true
   Timing: Generation 20.549 ms, Inlining 0.000 ms, Optimization 4.256 ms, Emission 138.020 ms, Total 162.825 ms
```

### 2: Индексация
После создания базовых индексов по ID и композитного индекса по статусу/дате, планировщик переключился на использование `Bitmap Index Scan`. Время выполнения сократилось до 7.6 секунд. Узким местом оставался Hash Join с полной вычиткой (Seq Scan) таблицы `order_product`.

**Результат:**
`Time: 7621.245 ms`

### 3: Оптимизация
Для улучшения производительности был создан покрывающий индекс `idx_order_product_order_id_quantity`, 
включающий в себя поле `quantity`, что позволило бд использовать `Index Only Scan`.

**Результат:**
`Time: 3540.606 ms`

**Итоговый план выполнения:**
```text
Finalize GroupAggregate  (cost=180131.74..180154.79 rows=91 width=12) (actual time=5018.265..5043.625 rows=7 loops=1)
   Group Key: o.date_created
   ->  Gather Merge  (cost=180131.74..180152.97 rows=182 width=12) (actual time=5018.234..5043.585 rows=21 loops=1)
         Workers Planned: 2
         Workers Launched: 2
         ->  Sort  (cost=179131.72..179131.94 rows=91 width=12) (actual time=4931.425..4931.429 rows=7 loops=3)
               Sort Key: o.date_created
               Sort Method: quicksort  Memory: 25kB
               Worker 0:  Sort Method: quicksort  Memory: 25kB
               Worker 1:  Sort Method: quicksort  Memory: 25kB
               ->  Partial HashAggregate  (cost=179127.85..179128.76 rows=91 width=12) (actual time=4931.350..4931.357 rows=7 loops=3)
                     Group Key: o.date_created
                     Batches: 1  Memory Usage: 24kB
                     Worker 0:  Batches: 1  Memory Usage: 24kB
                     Worker 1:  Batches: 1  Memory Usage: 24kB
                     ->  Nested Loop  (cost=3248.01..178634.52 rows=98665 width=8) (actual time=121.873..4842.996 rows=82517 loops=3)
                           ->  Parallel Bitmap Heap Scan on orders o  (cost=3247.58..68915.86 rows=98664 width=12) (actual time=121.644..2768.893 rows=82517 loops=3)
                                 Recheck Cond: (((status)::text = 'shipped'::text) AND (date_created > (now() - '7 days'::interval)))
                                 Heap Blocks: exact=21765
                                 ->  Bitmap Index Scan on idx_orders_status_date  (cost=0.00..3188.38 rows=236794 width=0) (actual time=131.686..131.686 rows=247550 loops=1)
                                       Index Cond: (((status)::text = 'shipped'::text) AND (date_created > (now() - '7 days'::interval)))
                           ->  Index Only Scan using idx_order_product_order_id_quantity on order_product op  (cost=0.43..1.10 rows=1 width=12) (actual time=0.022..0.023 rows=1 loops=247550)
                                 Index Cond: (order_id = o.id)
                                 Heap Fetches: 0
 Planning Time: 6.313 ms
 JIT:
   Functions: 39
   Options: Inlining false, Optimization false, Expressions true, Deforming true
   Timing: Generation 21.581 ms, Inlining 0.000 ms, Optimization 2.896 ms, Emission 85.879 ms, Total 110.357 ms
```

## Выводы
1. Нормализация данных позволила устранить избыточность и подготовить базу к индексированию.
2. Использование базовых индексов сократило нагрузку на фильтрацию, но для улучшения производительности потребовалось создание покрывающих индексов.