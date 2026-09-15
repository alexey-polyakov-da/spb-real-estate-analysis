/* Проект первого модуля: анализ данных для агентства недвижимости
 * Часть 2. Решаем ad hoc задачи
 *
 * Автор: Поляков Алексей
 * Дата:14.02.2026
*/

-- Задача 1: Время активности объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS(
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Выведем объявления без выбросов:
--SELECT *
--FROM real_estate.flats
--WHERE id IN (SELECT * FROM filtered_id);
-- CTE 3: Подготавливаем данные с категориями и вычисляем цену/кв.м
-- CTE 3: Подготавливаем данные с категориями и вычисляем цену/кв.м
prepared_data AS (
    SELECT 
        f.id,
        f.city_id,
        c.city,
        t.type,
        f.total_area,
        f.rooms,
        f.ceiling_height,
        f.balcony,
        f.living_area,
        f.is_apartment,
        f.open_plan,           
        a.first_day_exposition,
        a.days_exposition,     
        a.last_price,
        -- Категоризация по региону на основе ПЕРЕДЕЛАЛ теперь через city_id
        CASE 
            WHEN f.city_id = (SELECT city_id FROM real_estate.city WHERE city = 'Санкт-Петербург') THEN 'Санкт-Петербург'
            ELSE 'ЛенОбл'
        END AS region,
        -- Категоризация по дням активности
        CASE 
            WHEN a.days_exposition IS NULL OR a.days_exposition = 0 THEN 'Активные объявления' 
            WHEN a.days_exposition BETWEEN 1 AND 30 THEN 'до 1 месяца'                     
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'от 1 до 3 месяцев'                   
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'от 3 месяцев до полугода'                 
            ELSE 'более полугода'                                                             
        END AS activity_category,
        -- Цена за квадратный метр
        a.last_price / NULLIF(f.total_area, 0) AS price_per_sqm
    FROM real_estate.flats f
    JOIN real_estate.advertisement a ON f.id = a.id                                    
    JOIN real_estate.city c ON f.city_id = c.city_id                                   
    JOIN real_estate.type t ON f.type_id = t.type_id                                   
    CROSS JOIN limits                                                                  
    WHERE f.id IN (SELECT id FROM filtered_id)                                         
      AND t.type = 'город'                                                             
      AND EXTRACT(YEAR FROM a.first_day_exposition) BETWEEN 2015 AND 2018              
),
-- CTE 4: Группируем данные и считаем агрегаты
grouped_data AS (
    SELECT 
        region,
        activity_category,
        COUNT(*) AS total_ads,                             -- Общее количество объявлений
        -- Статистика по цене/кв.м
        AVG(price_per_sqm) AS avg_price_per_sqm_raw,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_per_sqm) AS median_price_per_sqm_raw,
        -- Статистика по площади
        AVG(total_area) AS avg_total_area_raw,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY total_area) AS median_total_area_raw,
        -- Статистика по комнатам и балконам
        AVG(rooms) AS avg_rooms_raw,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rooms) AS median_rooms_raw,
        AVG(balcony) AS avg_balcony_raw,
        PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY balcony) AS median_balcony_raw,
        -- Другие характеристики
        AVG(ceiling_height) AS avg_ceiling_height_raw,
        AVG(open_plan::int) AS open_plan_share_raw,        -- Доля с открытой планировкой
        AVG(is_apartment::int) AS apartment_share_raw,     -- Доля апартаментов
        -- Общее количество по региону для долей
        SUM(COUNT(*)) OVER (PARTITION BY region) AS region_total
    FROM prepared_data
    GROUP BY region, activity_category
)
-- ===== ФИНАЛЬНЫЙ ВЫВОД: СВОДНАЯ ТАБЛИЦА =====
SELECT 
    region,                    -- Санкт-Петербург или ЛенОбл
    activity_category,         -- Категория по дням активности
    total_ads,                 -- Количество объявлений
        -- Доля объявлений в регионе (%)
    ROUND(100.0::numeric * total_ads::numeric / region_total::numeric, 2) AS ads_share_percent,
        -- Цена за кв.м (руб)
    ROUND(avg_price_per_sqm_raw::numeric, 0) AS avg_price_per_sqm,
    ROUND(median_price_per_sqm_raw::numeric, 0) AS median_price_per_sqm,
        -- Площадь (кв.м)
    ROUND(avg_total_area_raw::numeric, 2) AS avg_total_area,
    ROUND(median_total_area_raw::numeric, 2) AS median_total_area,
        -- Комнаты и балконы
    ROUND(avg_rooms_raw::numeric, 2) AS avg_rooms,
    ROUND(median_rooms_raw::numeric, 2) AS median_rooms,
    ROUND(avg_balcony_raw::numeric, 2) AS avg_balcony,
    ROUND(median_balcony_raw::numeric, 2) AS median_balcony,
        -- Высота потолков (м)
    ROUND(avg_ceiling_height_raw::numeric, 2) AS avg_ceiling_height,
        -- Доли характеристик (%)
    ROUND(100.0::numeric * open_plan_share_raw::numeric, 2) AS open_plan_share_percent,
    ROUND(100.0::numeric * apartment_share_raw::numeric, 2) AS apartment_share_percent
FROM grouped_data
ORDER BY region, 
    CASE activity_category 
        WHEN 'Активные объявления' THEN 0 
        WHEN 'до 1 месяца' THEN 1 
        WHEN 'от 1 до 3 месяцев' THEN 2 
        WHEN 'от 3 месяцев до полугода' THEN 3 
        WHEN 'более полугода' THEN 4 
    END;     -- Сортировка категорий в логическом порядке
    
    
-- Задача 2: Сезонность объявлений
-- Определим аномальные значения (выбросы) по значению перцентилей:
-- Ррусская локаль для названий месяцев
SET lc_time = 'ru_RU.UTF-8';
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
dates AS (
    SELECT 
        a.id,
        EXTRACT(MONTH FROM a.first_day_exposition) AS publish_month_num,
        EXTRACT(MONTH FROM (a.first_day_exposition + INTERVAL '1 day' * a.days_exposition)) AS remove_month_num
    FROM real_estate.advertisement a
    JOIN filtered_id f ON a.id = f.id
    WHERE 
        a.first_day_exposition >= '2015-01-01'
        AND a.first_day_exposition < '2019-01-01'
        AND (a.first_day_exposition + INTERVAL '1 day' * a.days_exposition) < '2019-01-01'
        AND (a.first_day_exposition + INTERVAL '1 day' * a.days_exposition) >= '2015-01-01'
),
stats_by_publish AS (
    SELECT 
        publish_month_num,
        COUNT(*) AS ad_count,
        AVG(a.last_price / f.total_area) AS avg_price_per_sqm,
        AVG(f.total_area) AS avg_total_area
    FROM dates d
    JOIN real_estate.advertisement a ON d.id = a.id
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.city c ON f.city_id = c.city_id
    JOIN real_estate.type t ON f.type_id = t.type_id
    WHERE t.type = 'город'
    GROUP BY publish_month_num
),
stats_by_remove AS (
    SELECT 
        remove_month_num,
        COUNT(*) AS ad_count,
        AVG(a.last_price / f.total_area) AS avg_price_per_sqm,
        AVG(f.total_area) AS avg_total_area
    FROM dates d
    JOIN real_estate.advertisement a ON d.id = a.id
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.city c ON f.city_id = c.city_id
    JOIN real_estate.type t ON f.type_id = t.type_id
    WHERE t.type = 'город'
    GROUP BY remove_month_num
)
SELECT 
    CASE month_num -- Для того, чтобы месяцы были в именительном падеже с заглавной буквы
        WHEN 1 THEN 'Январь'
        WHEN 2 THEN 'Февраль'
        WHEN 3 THEN 'Март'
        WHEN 4 THEN 'Апрель'
        WHEN 5 THEN 'Май'
        WHEN 6 THEN 'Июнь'
        WHEN 7 THEN 'Июль'
        WHEN 8 THEN 'Август'
        WHEN 9 THEN 'Сентябрь'
        WHEN 10 THEN 'Октябрь'
        WHEN 11 THEN 'Ноябрь'
        WHEN 12 THEN 'Декабрь'
    END AS month_name,
    COALESCE(p.ad_count, 0) AS publish_count,
    COALESCE(r.ad_count, 0) AS remove_count,
    ROUND(COALESCE(p.avg_price_per_sqm, 0)::numeric, 4) AS publish_avg_price_sqm,
    ROUND(COALESCE(r.avg_price_per_sqm, 0)::numeric, 4) AS remove_avg_price_sqm,
    ROUND(COALESCE(p.avg_total_area, 0)::numeric, 4) AS publish_avg_area,
    ROUND(COALESCE(r.avg_total_area, 0)::numeric, 4) AS remove_avg_area
FROM (
    SELECT generate_series(1, 12) AS month_num
) months
LEFT JOIN stats_by_publish p ON months.month_num = p.publish_month_num
LEFT JOIN stats_by_remove r ON months.month_num = r.remove_month_num
ORDER BY months.month_num;
