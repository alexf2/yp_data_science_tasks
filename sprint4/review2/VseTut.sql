/* Проект «Разработка витрины и решение ad-hoc задач»
 * Цель проекта: подготовка витрины данных маркетплейса «ВсёТут»
 * и решение четырех ad hoc задач на её основе
 * 
 * Автор: Федоров Алексей Анатольевич
 * Дата: 17.02.2026
*/


/* Часть 1. Разработка витрины данных
 * Напишите ниже запрос для создания витрины данных
*/

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
  )
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
 

/* Часть 2. Решение ad hoc задач
 * Для каждой задачи напишите отдельный запрос.
 * После каждой задачи оставьте краткий комментарий с выводами по полученным результатам.
*/

/* Задача 1. Сегментация пользователей 
 * Разделите пользователей на группы по количеству совершённых ими заказов.
 * Подсчитайте для каждой группы общее количество пользователей,
 * среднее количество заказов, среднюю стоимость заказа.
 * 
 * Выделите такие сегменты:
 * - 1 заказ — сегмент 1 заказ
 * - от 2 до 5 заказов — сегмент 2-5 заказов
 * - от 6 до 10 заказов — сегмент 6-10 заказов
 * - 11 и более заказов — сегмент 11 и более заказов
*/

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


/* Напишите краткий комментарий с выводами по результатам задачи 1.
 * 
*/
Большинство делает один заказ и мизерное число больше 5-ти заказов. При этом, средняя стоимость заказа падает с увеличением их числа.


/* Задача 2. Ранжирование пользователей 
 * Отсортируйте пользователей, сделавших 3 заказа и более, по убыванию среднего чека покупки.  
 * Выведите 15 пользователей с самым большим средним чеком среди указанной группы.
*/

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


/* Напишите краткий комментарий с выводами по результатам задачи 2.
 * 
*/
Пользователей, с высокой стоимостью заказов от 5000 до 14000 немного, есть в каждом регионе, но больше в Москве.
Чемпион в СПБ.


/* Задача 3. Статистика по регионам. 
 * Для каждого региона подсчитайте:
 * - общее число клиентов и заказов;
 * - среднюю стоимость одного заказа;
 * - долю заказов, которые были куплены в рассрочку;
 * - долю заказов, которые были куплены с использованием промокодов;
 * - долю пользователей, совершивших отмену заказа хотя бы один раз.
*/

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

/* Напишите краткий комментарий с выводами по результатам задачи 3.
 * 
*/
Больше всего покупателей и заказов в Москве, но активность выше в СПБ. В Москве больше отмен. В СПБ выше стоимость заказа, использование переводов и купонов на скидку.
В Новосибирске меньше всего отмен.


/* Задача 4. Активность пользователей по первому месяцу заказа в 2023 году
 * Разбейте пользователей на группы в зависимости от того, в какой месяц 2023 года они совершили первый заказ.
 * Для каждой группы посчитайте:
 * - общее количество клиентов, число заказов и среднюю стоимость одного заказа;
 * - средний рейтинг заказа;
 * - долю пользователей, использующих денежные переводы при оплате;
 * - среднюю продолжительность активности пользователя.
*/

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

/* Напишите краткий комментарий с выводами по результатам задачи 4.
 * 
Больше всего пользователей приходят в ноябре и больше покупают. В январе сильный спад активности. Летом активность ровная. 
В сентябре максимальные стоимости заказов. Рейтинги покупок равномерные, но в последние 3 месяца года падают. 
Время активности пользователя максимально в январе (12 дней) и падает в последние 3 месяца года до 2-3-х дней. Остальные месяцы 5-7 дней.
