-- Сегментация пользователей по количеству заказов
SELECT
	segment,
	COUNT(distinct user_id) users_in_segment,
	round(AVG(total_orders), 1) avg_orders,
	-- round(AVG(avg_order_cost), 2) avg_order_cost
	-- используем не простое среднее, а взвешенное среднее, чтобы учесть вес пользователя
	-- чем больше число заказов, тем больше вес
	round(SUM(total_order_costs) / SUM(total_orders), 2) avg_order_cost
FROM
	(SELECT 
	    user_id, total_orders, avg_order_cost, total_order_costs,
	    CASE 
	        WHEN total_orders = 1 THEN '1 заказ'
	        WHEN total_orders BETWEEN 2 AND 5 THEN '2-5 заказов'
	        WHEN total_orders BETWEEN 6 AND 10 THEN '6-10 заказов'
	        WHEN total_orders >= 11 THEN '11 и более заказов'
	        ELSE 'неизвестно'
	    END AS segment
	FROM ds_ecom.product_user_features) drv
GROUP by segment
ORDER BY avg_order_cost DESC;

-- Топ-15 пользователей по средней стоимости заказа
SELECT 
	region,
    user_id,
    RANK() OVER(ORDER BY avg_order_cost DESC) rank,
    total_orders,
    ROUND(avg_order_cost, 2) AS avg_order_cost
FROM ds_ecom.product_user_features
WHERE total_orders >= 3
ORDER BY avg_order_cost DESC
LIMIT 15;

-- Статистика по регионам
SELECT 
    region,
    COUNT(user_id) AS users_count,
    SUM(total_orders) AS orders_count,
    ROUND(AVG(avg_order_cost), 2) AS avg_order_cost,
    ROUND(SUM(num_installment_orders)::NUMERIC / NULLIF(SUM(total_orders), 0) * 100, 2) || '%' AS installment_orders_percent,
    ROUND(SUM(num_orders_with_promo)::NUMERIC / NULLIF(SUM(total_orders), 0) * 100, 2) || '%' AS promo_orders_percent,
    ROUND(AVG(used_cancel) * 100, 2) || '%' AS cancelled_users_percent
FROM ds_ecom.product_user_features
GROUP BY region
ORDER BY region;

-- Активность по месяцам первого заказа
SELECT 
    EXTRACT(MONTH FROM first_order_ts) AS month_num,
    TO_CHAR(first_order_ts, 'Mon YYYY') AS month_name,
    COUNT(DISTINCT user_id) AS users_count,
    SUM(total_orders) AS orders_count,
    ROUND(AVG(avg_order_cost), 2) AS avg_order_cost,
    ROUND(AVG(avg_order_rating), 2) AS avg_order_rating,
    ROUND(SUM(used_money_transfer)::NUMERIC / COUNT(DISTINCT user_id) * 100, 1) || '%' AS used_money_transfer_percent,
    EXTRACT(DAY FROM AVG(lifetime))::INT || ' days ' || 
    EXTRACT(HOUR FROM AVG(lifetime))::INT || ' hours' AS avg_lifetime
FROM ds_ecom.product_user_features
WHERE first_order_ts::DATE >= '2023-01-01' 
  AND first_order_ts::DATE < '2024-01-01'
GROUP BY EXTRACT(MONTH FROM first_order_ts), 
         TO_CHAR(first_order_ts, 'Mon YYYY')
ORDER BY month_num;
