-- Выявление дефектов и аномалий данных

-- 1. Оценки заказов (смотрим значения и сколько их бывает у заказа)
SELECT DISTINCT review_score
FROM order_reviews
ORDER BY
	review_score
	
-- шкала оценок разная: 1-5 и 10-15, нужно првести к одной шкале по месту
-- FIX: приводим через CASE к 1 - 5 деленим
SELECT CASE 
		WHEN review_score >= 10 THEN review_score / 10
ELSE review_score
	END
FROM order_reviews
GROUP BY
	CASE 
		WHEN review_score >= 10 THEN review_score / 10
ELSE review_score
	END
ORDER BY
	review_score
	
-- 2. Число товаров в покупке: здесь есть пустые заказы
-- FIX: это отменённые заказы, поэтому достаточно LEFT JOIN, чтобы не пропали такие ордера
-- или, может применить INNER JOIN, и тогда их не будет? 
SELECT order_id, order_status, count(order_item_id) cnt, count(*) OVER(PARTITION BY order_status)
FROM orders o
LEFT JOIN order_items oi
	USING(order_id)
WHERE order_status = 'Отменено'
GROUP BY
	order_id
HAVING
	count(order_item_id) = 0
-- тут пустых нет
SELECT order_id, order_status, count(order_item_id) cnt, count(*) OVER(PARTITION BY order_status)
FROM orders o
LEFT JOIN order_items oi
	USING(order_id)
WHERE order_status = 'Доставлено'
GROUP BY
	order_id
HAVING
	count(order_item_id) = 0
	
-- 3. Число оценок у одного заказа: есть заказы с двумя оценками, оценки могут быть разные
-- и по разным шкалам
-- FIX: усреднять оценку, приведённую к 1 - 5
SELECT order_id, count(orw.order_id), min(review_score), max(review_score)
FROM orders o
JOIN order_reviews orw
	USING(order_id)
WHERE order_status = 'Отменено'
OR order_status = 'Доставлено'
GROUP BY
	order_id
HAVING
	count(orw.order_id) > 1
-- заказов без оценки нет
SELECT order_id, count(orw.order_id), min(review_score), max(review_score)
FROM orders o
JOIN order_reviews orw
	USING(order_id)
GROUP BY
	order_id
HAVING
	count(orw.order_id) = 0
	
-- 4. стоимости заказов, есть эксцессы
-- FIX: надо применять взешенную оценку средних, чтобы 11 гигантских заказов не искажали
-- см. следующий запрос
SELECT order_id, sum(price + delivery_cost) COST
FROM orders o
LEFT JOIN order_items oi
	USING(order_id)
WHERE order_status = 'Отменено'
OR order_status = 'Доставлено'
GROUP BY
	order_id
HAVING
	count(order_item_id) > 0
ORDER BY
	COST DESC
	
-- средний ордер без учёта пустых ордеров 3 511 руб, min: 198 руб, max: 296 740 руб
-- normal_orders = 52825 штук, очень большие 2433, супер большие 11 штук, очень маленькие 5775
-- медианный ордер: 2 250 руб
SELECT avg(COST), percentile_cont(0.5) WITHIN GROUP (
ORDER BY COST) median_by_category, min(COST), max(COST), count(*) FILTER(WHERE COST > 100000) extra_high_orders, count(*) FILTER(WHERE COST > 15000) very_high_orders, count(*) FILTER(WHERE COST > 5522 AND COST <= 15000) high_orders, count(*) FILTER(WHERE COST > 1500 AND COST <= 5522) normal_orders, count(*) FILTER(WHERE COST >= 700 AND COST <= 1500) low_orders, count(*) FILTER(WHERE COST < 700) very_low_orders
FROM(
	SELECT order_id, sum(price + delivery_cost) COST
FROM orders o
LEFT JOIN order_items oi
	USING(order_id)
WHERE order_status = 'Отменено'
OR order_status = 'Доставлено'
GROUP BY
		order_id
HAVING
		count(order_item_id) > 0
ORDER BY
		COST DESC
) drv

-- 5. последовательность платежей: есть случаи, когда начинается со 2-го платежа
-- FIX: в подсчёте флага BOOL_OR(payment_type = 'денежный перевод' AND payment_sequential IN (1, 2)) has_money_transfer
SELECT order_id, min(payment_sequential), max(payment_sequential), count(*)
FROM orders o
LEFT JOIN order_payments op
	USING(order_id)
WHERE order_status = 'Отменено'
OR order_status = 'Доставлено'
GROUP BY
	order_id
HAVING
	count(*) > 5
-- having count(*) > 1 and min(payment_sequential) > 1
-- order by 2 desc

SELECT *
FROM order_payments
WHERE order_id = 'cc78407c0a27d3450010482ad091d498'

SELECT *
FROM order_payments
WHERE order_id = 'a079628ac8002126e75f86b0f87332e4'

SELECT *
FROM order_payments
WHERE order_id = '0b47f5e9432bd433f8c5cf64e60e6e5f'

-- есть один заказ, который доставлен, но не оплачен
-- FIX: у таких заказов в витрине будет has_money_transfer = 0
SELECT order_id, min(payment_sequential), max(payment_sequential)
FROM orders o
LEFT JOIN order_payments op
	USING(order_id)
WHERE order_status = 'Доставлено'
GROUP BY
	order_id
HAVING
	min(payment_sequential) IS NULL
ORDER BY
	2 DESC
