-- task 1 
-- cities with more than one airport
  SELECT city, COUNT(airport_code) AS airport_number
    FROM bookings.airports
GROUP BY city
  HAVING COUNT(airport_code) > 1;

	-- all cities with airports
	SELECT COUNT(DISTINCT city)
  	FROM bookings.airports; -- 101

-- task 2 --
/*Select aiport with planes with maximum RANGE */
 EXPLAIN analyse
    WITH super_craft (craft_code)
      AS (
	       SELECT aircraft_code
	         FROM bookings.aircrafts
         ORDER BY range DESC LIMIT 1 --'773'
         )
   SELECT DISTINCT UNNEST (array_agg( ARRAY [r.departure_airport_name, r.arrival_airport_name] ))
          AS airport_name
     FROM bookings.routes r
   WHERE  r.aircraft_code IN  -- routes with appropritate plane
         ( SELECT craft_code FROM super_craft );
ORDER BY r.flight_no, r.departure_airport_name;	

		-- aircraft with maximum range
	  SELECT aircraft_code, model AS aircraft_model, range
    	FROM bookings.aircrafts
	ORDER BY range DESC LIMIT 1;


		-- task 3
-- bookings without flight
EXPLAIN ANALYSE
 SELECT EXISTS (
     	    SELECT b.book_ref
     	      FROM bookings.bookings b
         LEFT JOIN ( -- all bookings with information about bp
                    SELECT t.book_ref AS book_ref -- bookings with boarding pass
                      FROM bookings.tickets t
                     WHERE t.ticket_no IN
                           ( 
                            SELECT ticket_no -- tickets with boarding pass
                              FROM bookings.boarding_passes bp 
                           )
                     ) AS t2
                 ON b.book_ref = t2.book_ref
              WHERE t2.book_ref IS NULL -- but without ticket
             );


	-- EXPLAIN ANALYSE
	-- percent of bookings without boarding pass
 	SELECT (all_bookings.total - bookings_with_bp.total) > 0,
 			all_bookings.total - bookings_with_bp.total,
 			all_bookings.total,
	        (all_bookings.total - bookings_with_bp.total)/CAST(all_bookings.total AS float) * 100
	   FROM  
	        ( SELECT COUNT( DISTINCT t.book_ref ) -- number of bookings with bp
	              AS total
	            FROM bookings.tickets t
	           WHERE t.ticket_no
	              IN
	                 ( -- tickets with boarding pass
	                   SELECT ticket_no
	                     FROM bookings.boarding_passes bp 
	                 )
	        ) AS bookings_with_bp,        
	        (
	          SELECT COUNT( b.book_ref ) -- total number of bookings
	              AS total
	            FROM bookings.bookings b
	         ) AS all_bookings;
	     
	    -- task 4
-- percent of flights
--EXPLAIN ANALYSE 
    WITH all_flights(total)
      AS ( -- count total number of flights
          SELECT COUNT(*)
          FROM bookings.flights f
          WHERE f.status <> 'Cancelled'
         )
  SELECT ac.model,
         ROUND(100.0 * r2.aircraft_flights / all_flights.total, 1) AS flights_percent
    FROM all_flights,
         (
            SELECT r.aircraft_code, -- number of flights per plane model
             COUNT(r.flight_no) AS aircraft_flights
              FROM bookings.flights r
             WHERE r.status <> 'Cancelled'            
          GROUP BY r.aircraft_code
         ) AS r2
    JOIN bookings.aircrafts ac USING(aircraft_code)
ORDER BY flights_percent DESC
   LIMIT 3;
  
		-- task 5
-- Business chiper than Economy
-- EXPLAIN ANALYZE 
WITH min_a_per_fare_flight(flight_id, f_cond, amount)
  AS (  -- minimum cost for every flight for each fare condition 
      SELECT tf2.flight_id, tf2.fare_conditions,
             min(tf2.amount)
        FROM bookings.ticket_flights tf2
    GROUP BY tf2.flight_id, tf2.fare_conditions
     )
    SELECT EXISTS
           (
            SELECT f.arrival_city, f.departure_city
              FROM  bookings.flights_v f
         LEFT JOIN ( -- add cost of business fare for each flight
			        SELECT *
			          FROM min_a_per_fare_flight
			         WHERE f_cond = 'Business'
		           ) AS business_fees
	            ON business_fees.flight_id = f.flight_id
         LEFT JOIN ( -- add cost of economy fare for each flight
			        SELECT *
			          FROM min_a_per_fare_flight
			         WHERE f_cond = 'Economy'
		           ) AS economy_fees
	            ON economy_fees.flight_id = f.flight_id
          GROUP BY f.arrival_city, f.departure_city -- group by route
            HAVING min(economy_fees.amount) > min(business_fees.amount) -- business is cheaper
            );
 
		-- task 6
-- maximum depature delay
-- EXPLAIN analyse
SELECT MAX(actual_departure - scheduled_departure)
	AS max_delay
  FROM bookings.flights f;
 
 		-- task 7
-- cities without straight flights
WITH city_pairs(departure_city, arrival_city)
  AS ( -- all pairs of cities from routes
         SELECT DISTINCT r.departure_city, r2.arrival_city
           FROM bookings.routes r
           LEFT OUTER JOIN bookings.routes r2
             ON r.departure_city <> r2.arrival_city
          -- chose one-way routes
          WHERE r.departure_city < r2.arrival_city
      ORDER  BY r.departure_city, r2.arrival_city
     )
         SELECT c_p.departure_city AS firts_city,
                c_p.arrival_city   AS second_city
           FROM city_pairs c_p
       LEFT JOIN bookings.routes r -- compare with real flights
             ON c_p.departure_city = r.departure_city
                AND c_p.arrival_city = r.arrival_city
          WHERE r.departure_city IS NULL -- exclude real flights
       ORDER BY c_p.departure_city, c_p.arrival_city;

		-- task 8
-- cities with changes
-- EXPLAIN ANALYSE
WITH my_q AS (
   SELECT t.passenger_id,
      	  LAG(f_v.scheduled_departure) OVER w AS first_dep,
   		  LAG(f_v.scheduled_arrival  ) OVER w AS first_ar,
   		      f_v.scheduled_departure AS dep_time,
   		      f_v.scheduled_arrival AS ar_time,
          LAG(f_v.scheduled_arrival ) OVER w - f_v.scheduled_departure AS change_time,
          LAG(f_v.departure_city ) OVER w AS first_city,
             f_v.departure_city AS change_city,
          f_v.arrival_city AS second_city
     FROM bookings.tickets AS t  -- passenger identity
LEFT JOIN bookings.ticket_flights AS tf -- flight idetity
          USING(ticket_no)
LEFT JOIN bookings.flights_v AS f_v -- cities
          USING(flight_id)
   WINDOW w AS (PARTITION BY t.passenger_id ORDER BY f_v.scheduled_departure ASC)
   )
   SELECT DISTINCT q2.first_city, q2.second_city
          --q2.passenger_id, q2.dep_time, q2.ar_time, q2.change_time,
          --q2.first_city, q2.change_city, q2.second_city
     FROM my_q AS q2
    WHERE q2.change_time IS NOT NULL
          AND q2.change_time > INTERVAL '-24 hours'
          AND q2.first_city < q2.second_city
 ORDER BY q2.first_city, q2.second_city;

         -- task 9
-- airports with straight flights
CREATE OR REPLACE FUNCTION dist (lon_1 FLOAT, lat_1 FLOAT, lon_2 FLOAT, lat_2 FLOAT)
RETURNS FLOAT AS $$
DECLARE R integer;
        d float;
BEGIN 
  R = 6371;
  lon_1 = radians(lon_1);
  lat_1 = radians(lat_1);
  lon_2 = radians(lon_2);
  lat_2 = radians(lat_2);
  d = acos( sin(lat_1)*sin(lat_2) + cos(lat_1)*cos(lat_2)*cos(lon_1 - lon_2) );
  RETURN d * R;
END; $$
LANGUAGE PLPGSQL;

   SELECT r.departure_airport_name AS first_airport, -- r.departure_airport,
          -- dep_a.longitude, dep_a.latitude,
          r.arrival_airport_name AS second_airport, -- r.arrival_airport,
          -- arr_a.longitude, arr_a.latitude, 
          dist(dep_a.longitude, dep_a.latitude, arr_a.longitude, arr_a.latitude) AS distance_km,
          a.RANGE, a.model, 
          dist(dep_a.longitude, dep_a.latitude, arr_a.longitude, arr_a.latitude) < a.RANGE AS range_is_ok
     FROM bookings.routes r
LEFT JOIN bookings.airports dep_a -- add departure airport info
       ON dep_a.airport_name = r.departure_airport_name
LEFT JOIN bookings.airports arr_a -- add arrival airport info
       ON arr_a.airport_name  = r.arrival_airport_name
LEFT JOIN bookings.aircrafts a  -- add aircraft info
          USING(aircraft_code)
    WHERE r.departure_airport_name < r.arrival_airport_name -- sort return flights
 ORDER BY r.departure_airport_name, r.arrival_airport_name;
 

select departure_airport, airports.coordinates as x, arrival_airport, fo.coordinates as y, 
(acos(sin(radians(airports.coordinates[1]))*sin(radians(fo.coordinates[1])) +cos(radians(airports.coordinates[1]))*
cos(radians(fo.coordinates[1]))*cos(radians(airports.coordinates[0] - fo.coordinates[0])))*6371)::integer as "����������", range
from 
	(select distinct departure_airport, arrival_airport, aircraft_code 
	from bookings.flights) as foo
join bookings.airports on foo.departure_airport = airports.airport_code
join bookings.airports as fo on foo.arrival_airport = fo.airport_code
join bookings.aircrafts on bookings.aircrafts.aircraft_code = foo.aircraft_code
order by arrival_airport
