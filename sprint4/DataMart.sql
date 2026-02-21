CREATE MATERIALIZED VIEW ds_ecom.product_user_features2 AS
with  
  -- 3 самые активных региона для фильтра
  top_regions AS ( 
    SELECT 
    	region
    from ds_ecom.users u2 JOIN ds_ecom.orders o2 USING (buyer_id)
    WHERE order_status IN ('Доставлено', 'Отменено')
    GROUP by region
    ORDER by COUNT(order_id) DESC
    limit 3
  ),  
  -- Базовая информация о клиенте и времени его активности
  user_info AS (
    SELECT
      u.user_id,      
      u.region,
      MIN(o.order_purchase_ts) first_order_ts,
      MAX(o.order_purchase_ts) last_order_ts,
      MAX(o.order_purchase_ts)::date - MIN(o.order_purchase_ts)::date lifetime
    FROM
      ds_ecom.users u JOIN ds_ecom.orders o USING (buyer_id)
    WHERE region IN (select region from top_regions) AND order_status IN ('Доставлено', 'Отменено')
    GROUP by u.user_id, u.region
  ),  
  -- Тут считаем рейтинги ордеров: иногда бывает по две оценки на один ордер
  order_reviews AS (
  	SELECT 
  		order_id,
  		AVG(
          	CASE WHEN review_score > 5 then review_score / 10 else review_score END
        ) order_score
        FROM ds_ecom.orders o LEFT JOIN ds_ecom.order_reviews orw USING(order_id)
        WHERE order_status IN ('Доставлено', 'Отменено')
    	GROUP by o.order_id
  ),
  -- Информация о заказах клиента
  user_orders AS (
    SELECT
      *,
      num_canceled_orders::NUMERIC / NULLIF(total_orders, 0) canceled_orders_ratio
    FROM
      (
        SELECT
          u.user_id,
          u.region,
          COUNT(DISTINCT o.order_id) total_orders,
          AVG(order_score) avg_order_rating,
          COUNT(order_score) num_orders_with_rating,
          COUNT(DISTINCT o.order_id) FILTER (where order_status = 'Отменено') num_canceled_orders
        FROM
          ds_ecom.users u JOIN ds_ecom.orders o USING (buyer_id)
          	LEFT JOIN order_reviews w USING (order_id)
        WHERE region IN (select region from top_regions) AND order_status IN ('Доставлено', 'Отменено')
        GROUP by u.user_id, u.region) drv
  ),  
  -- Тут считаем стоимость каждого ордера, попадаются пустые ордера
  order_cost AS (
    SELECT
      order_id,
      SUM(price + delivery_cost) cost
    FROM ds_ecom.order_items
    GROUP by order_id
  ),
  -- Тут считаем платёжную информацию по каждому ордеру
  order_payment_features AS (
    SELECT
      order_id,
      MAX(payment_installments) > 1 AS is_installment,
      COUNT(*) FILTER (WHERE payment_type = 'промокод') > 0 AS is_promo,
      BOOL_OR(payment_type = 'денежный перевод' AND payment_sequential IN (1, 2)) has_money_transfer
    FROM ds_ecom.order_payments
    GROUP by order_id
  ),  
  -- Информация о платежах
  user_payments AS (
    SELECT
      u.user_id,
      u.region,
      SUM(cost) FILTER(where order_status='Доставлено') total_order_costs,
      AVG(cost) FILTER(where order_status='Доставлено') avg_order_cost,
      COUNT(DISTINCT o.order_id) FILTER (where opf.is_installment) num_installment_orders,
      COUNT(DISTINCT o.order_id) FILTER (where opf.is_promo) num_orders_with_promo,
      BOOL_OR(has_money_transfer) used_money_transfer
    FROM
      ds_ecom.users u
      	JOIN ds_ecom.orders o USING (buyer_id)
      	-- могут быть пустые ордера
	    LEFT JOIN order_cost oc USING (order_id)
      	LEFT JOIN order_payment_features opf USING (order_id)
    WHERE
      region IN (select region from top_regions) AND order_status IN ('Доставлено', 'Отменено')
    GROUP by u.user_id, u.region),
   -- Флаги
  user_booleans AS (
    SELECT
      u.user_id,
      u.region,
      BOOL_OR(opf.is_installment) AS used_installments,
      BOOL_OR(order_status = 'Отменено') used_cancel,
      BOOL_OR(has_money_transfer) used_money_transfer
    FROM
      ds_ecom.users u
      	JOIN ds_ecom.orders o USING (buyer_id)
      	LEFT JOIN order_payment_features opf USING (order_id)
    where region IN (select region from top_regions) AND order_status IN ('Доставлено', 'Отменено')
    GROUP by u.user_id, u.region
  ),
SELECT	
  ui.user_id,
  ui.region,
  -- дата и время первого заказа
  first_order_ts,
  -- дата и время последнего заказа
  last_order_ts,
  -- жизненный цикл клиента, то есть сколько дней прошло между первым и последним заказом
  lifetime,
  -- общее количество заказов
  total_orders,
  -- средняя оценка, которую пользователь выставляет своим заказам
  avg_order_rating,
  --  количество заказов, для которых получена оценка с рейтингом
  num_orders_with_rating,
  -- количество отменённых заказов
  num_canceled_orders,
  -- доля отменённых заказов
  canceled_orders_ratio,
  -- суммарная стоимость всех доставленных пользователю заказов
  total_order_costs,
  -- средняя стоимость заказа
  avg_order_cost,
  -- количество заказов, оплаченных в рассрочку
  num_installment_orders,
  -- количество заказов, купленных с использованием промокодов для оплаты
  num_orders_with_promo,
  -- использовал ли клиент денежный перевод хотя бы один раз в качестве первого типа оплаты
  ub.used_money_transfer::INT used_money_transfer,
  --  использовал ли клиент рассрочку хотя бы один раз
  used_installments::INT used_installments,
  -- отменял ли клиент хотя бы один заказ
  used_cancel::INT used_cancel
FROM
  user_info ui
  	JOIN user_orders uo USING (user_id, region)
  	JOIN user_payments up USING (user_id, region)
  	JOIN user_booleans ub USING (user_id, region);
  	
 -- select count(*) 	 from ctef; -- 62478 rows

-- select count(*) from ds_ecom.product_user_features; -- 62073 rows



 