/* Проект «Секреты Тёмнолесья»
 * Цель проекта: изучить влияние характеристик игроков и их игровых персонажей 
 * на покупку внутриигровой валюты «райские лепестки», а также оценить 
 * активность игроков при совершении внутриигровых покупок
 * 
 * Автор: Федоров Алексей Анатольевич
 * Дата: 31.01.2026
*/

-- Часть 1. Исследовательский анализ данных
-- Задача 1. Исследование доли платящих игроков

-- 1.1. Доля платящих пользователей по всем данным:
/* v1 */
/*WITH cte1 AS (
	SELECT 
		count(*) total_users, 
		count(CASE WHEN payer = 1 THEN 1 ELSE NULL end) payer_users
	FROM fantasy.users
)
SELECT 
	total_users, 
	payer_users, 
	round(payer_users::numeric / total_users, 2) fraction_payers
FROM cte1*/

/* v2 */
1) Проверяем users на технические дубликаты: если teach_nickname повторяется, то это дефект
данных. Ещё возможет вариант, когда один человек имеет много учёток под разным именем. Тогда могут 
совпадать birthdate, loc_id, server, но для этой проверки полей недостаточно.

Запрос:
SELECT
	count(tech_nickname) cnt
FROM fantasy.users
GROUP BY tech_nickname
HAVING count(tech_nickname) <> 1
возвращает пустой результат, значит tech_nickname - естественный альтернативный ключ.

И переписываем исходный запрос проще и с %:
SELECT 
	count(*) total_users,
	sum(payer) payers_count,
	round(avg(payer) * 100.0, 1) payers_percent
FROM fantasy.users;


-- 1.2. Доля платящих пользователей в разрезе расы персонажа:
/* v1 */
/*WITH cte1 AS (
	SELECT 
		race_id,
		count(*) total_users, 
		count(CASE WHEN payer = 1 THEN 1 ELSE NULL end) payer_users
	FROM fantasy.users
	GROUP BY race_id
)
SELECT 
	race,
	total_users, 
	payer_users, 
	round(payer_users::numeric / total_users, 2) fraction_payers
FROM cte1 JOIN fantasy.race using(race_id)
ORDER BY race*/

/* v2 */
Переписал запрос проще, перешёл на %:
SELECT 
	race,
	count(*) total_users_of_race,
	sum(payer) payers_count_of_race,
	round(avg(payer) * 100.0, 1) payers_percent
FROM fantasy.users JOIN fantasy.race using(race_id)
GROUP BY race_id, race
ORDER BY payers_percent DESC;


-- Задача 2. Исследование внутриигровых покупок
-- 2.1. Статистические показатели по полю amount:
SELECT 
	count(*) total, 
	sum(amount) total_amount, 
	min(amount) min_amount, 
	max(amount) max_amount,
	round(avg(amount)::numeric, 2) avg_amount,
	percentile_disc(0.5) WITHIN GROUP (ORDER BY amount) mediane,
	round(stddev(amount)::NUMERIC, 2) dev_amount
FROM fantasy.events
WHERE amount > 0

-- 2.2: Аномальные нулевые покупки:
/* v1 */
/*WITH cte1 AS (
	SELECT 
		count(*) total, 
		count(CASE WHEN amount = 0 THEN 1 ELSE NULL end) zeros
	FROM fantasy.events
)
SELECT total, zeros, zeros::numeric/total fraction
FROM cte1*/

/* v2 */
Переписал запрос короче, и с процентами:

SELECT
	count(*) total_events,
	count(*) FILTER (WHERE amount = 0) zero_events,
	round(avg(CASE WHEN amount = 0 THEN 1 ELSE 0 END) * 100.0, 1) zero_events_percent
FROM fantasy.events;


-- 2.3: Популярные эпические предметы:
/* v1 */
/*WITH cte1 AS (
	SELECT item_code, count(*) sold_count
	FROM fantasy.events 
	WHERE amount > 0
	GROUP BY item_code
),
cte2 AS (
	SELECT count(*) total_sold
	FROM fantasy.events 
	WHERE amount > 0
),
cte3 AS (
	SELECT item_code, count(DISTINCT id) bayers_count
	FROM fantasy.events
	WHERE amount > 0
	GROUP BY item_code
),
cte4 AS (
	SELECT count(*) total_users
	FROM fantasy.users	
)
SELECT 
	i.game_items, 
	sold_count, 
	round(sold_count::numeric / cte2.total_sold  * 100.0, 2) fraction,
	round(bayers_count::numeric / cte4.total_users * 100.0, 2) fraction_users
FROM 
	cte1 JOIN fantasy.items i USING(item_code) 
	JOIN cte3 USING(item_code) 
	CROSS JOIN cte2 
	CROSS JOIN cte4
ORDER BY sold_count DESC; */

/* v2 */
SELECT 
	drv1.game_items,
    drv1.item_sold_count,
    drv1.bayers_count,
    round(drv1.item_sold_count::numeric / drv2.total_items_sold_count * 100.0, 1) item_sold_percent,
    round(drv1.bayers_count::numeric / drv2.total_bayers_count * 100.0, 1) bayers_count_percent
FROM 
	(SELECT
		game_items,
		count(DISTINCT id) bayers_count,
		count(*) item_sold_count
	 FROM fantasy.events ev JOIN fantasy.items i USING(item_code)
	 WHERE amount > 0
	 GROUP BY item_code, game_items
	) drv1		
	CROSS JOIN	
	(SELECT
		count(*) total_items_sold_count,
		count(DISTINCT id) total_bayers_count
	 FROM fantasy.events
	 WHERE amount > 0
	) drv2
ORDER BY drv1.item_sold_count DESC;
 
	

-- Часть 2. Решение ad hoc-задачbи
-- Задача: Зависимость активности игроков от расы персонажа:
-- Напишите ваш запрос здесь

/* v1 */
/*WITH cte1 AS (
	SELECT 
		u.race_id,
		race,
		count(*) race_count
	FROM fantasy.users u, fantasy.race r
	WHERE u.race_id = r.race_id
	GROUP BY u.race_id, r.race
),
cte2 AS (
	SELECT 
		race_id,
		count(DISTINCT e.id) buyer_count,
		count(e.transaction_id) total_purchases,
		avg(amount) avg_amount,
		sum(amount) total_amount
	FROM fantasy.users u LEFT JOIN fantasy.events e using(id)
	WHERE e.amount > 0
	GROUP BY u.race_id
),
cte3 AS (
	select 
		race_id,
		count(CASE WHEN payer = 1 THEN 1 ELSE NULL END) payer_count
	FROM fantasy.users u
	GROUP BY u.race_id
)
SELECT 		
	race, 
	race_count, 
	payer_count, 
	buyer_count,
	round(buyer_count::NUMERIC / race_count * 100.0, 2) relative_bayer,
	round(payer_count::NUMERIC / race_count * 100.0, 2) payer_fraction,	
	round(total_purchases::NUMERIC / buyer_count) avg_purcashes,
	round(avg_amount::NUMERIC, 2) avg_amount_of_purchse,
	round(total_amount::NUMERIC / buyer_count, 2) total_avg_amount
FROM cte1 JOIN cte2 using(race_id) JOIN cte3 using(race_id)
ORDER BY race_count DESC 
*/

/* v2 */
WITH cte1 AS (
	SELECT 
		u.race_id,
		race,
		count(*) race_count
	FROM fantasy.users u, fantasy.race r
	WHERE u.race_id = r.race_id
	GROUP BY u.race_id, r.race
),
cte2 AS (
	SELECT 
		race_id,
		count(DISTINCT e.id) buyer_count,
		count(e.transaction_id) total_purchases,
		avg(amount) avg_amount,
		sum(amount) total_amount
	FROM fantasy.users u LEFT JOIN fantasy.events e using(id)
	WHERE e.amount > 0
	GROUP BY u.race_id
),
cte3 AS (
	select 
		race_id,
		sum(payer) payer_count,
		round(avg(payer)* 100.0, 1) payer_percent 
	FROM fantasy.users
	WHERE id IN (SELECT id FROM fantasy.events WHERE amount > 0)
	GROUP BY race_id
)
SELECT 		
	race,
	-- число игроков данной рассы
	race_count, 
	-- число платящих игроков данной рассы
	payer_count, 
	-- число игроков данной рассы, совершающих ненулевые покупки 
	buyer_count,
	-- % игроков в рассе, кто совершает ненулевые покупки
	round(buyer_count::NUMERIC / race_count * 100.0, 1) bayer_percent,
	-- % игроков в рассе, кто платит	
	payer_percent,
	-- среднее колитество покупок у игрока рассы
	round(total_purchases::NUMERIC / buyer_count) avg_purchases,
	-- средняя стоимость покупки для игрока рассы
	round(avg_amount::NUMERIC, 2) avg_amount_of_purchase,
	-- средняя сумма всех покупок для игрока рассы
	round(total_amount::NUMERIC / buyer_count, 2) total_avg_amount
FROM cte1 JOIN cte2 using(race_id) JOIN cte3 using(race_id)
ORDER BY payer_percent DESC;


