-- =============================================================================
-- RoadLink Express — MIT 8103 Portfolio 1
-- 03_seed.sql — seed terminals, routes, buses, drivers, passengers
-- =============================================================================
-- Connect:
--   sudo runuser -u postgres -- psql -d roadlink -f 03_seed.sql
--
-- All dates are RELATIVE TO TODAY (CURRENT_DATE) so this script never expires.
-- =============================================================================

\set ON_ERROR_STOP on

TRUNCATE cancellation, payment, booking, trip, passenger, driver, bus, route, terminal RESTART IDENTITY CASCADE;

-- ---------------------------------------------------------------------------
-- terminals
-- ---------------------------------------------------------------------------
INSERT INTO terminal (city, name, address) VALUES
    ('Lagos',        'Jibowu Terminal',     '1 Jibowu Street, Yaba, Lagos'),
    ('Lagos',        'Ojota Terminal',      'Ikorodu Road, Ojota, Lagos'),
    ('Abuja',        'Utako Terminal',      'Utako District, Abuja FCT'),
    ('Ibadan',       'Iwo Road Terminal',    'Iwo Road, Ibadan, Oyo'),
    ('Enugu',        'Enugu Main Terminal',  'Old Park, Enugu'),
    ('Port Harcourt','PH Main Terminal',     'Eleme Junction, Port Harcourt'),
    ('Benin',        'Benin Main Terminal',  'Akpakpava, Benin City, Edo'),
    ('Kano',         'Kano Main Terminal',   'Zaria Road, Kano');

-- ---------------------------------------------------------------------------
-- routes (fares in ₦, distances in km — realistic Nigerian inter-city figures)
-- ---------------------------------------------------------------------------
INSERT INTO route (from_terminal_id, to_terminal_id, distance_km, base_fare_ngn)
SELECT f.terminal_id, t.terminal_id, d.km, d.fare
FROM terminal f
JOIN terminal t ON t.city <> f.city  -- but we want pairs we explicitly pick below
CROSS JOIN LATERAL (VALUES
    -- Lagos (Jibowu) → ...
    ('Lagos','Jibowu Terminal','Ibadan','Iwo Road Terminal',         130.0,  6500.00),
    ('Lagos','Jibowu Terminal','Benin','Benin Main Terminal',        320.0, 13500.00),
    ('Lagos','Jibowu Terminal','Abuja','Utako Terminal',             715.0, 23500.00),
    ('Lagos','Jibowu Terminal','Port Harcourt','PH Main Terminal',   650.0, 22000.00),
    -- Lagos (Ojota) → ...
    ('Lagos','Ojota Terminal','Ibadan','Iwo Road Terminal',          135.0,  6800.00),
    ('Lagos','Ojota Terminal','Kano','Kano Main Terminal',           980.0, 28500.00),
    -- Abuja (Utako) → ...
    ('Abuja','Utako Terminal','Lagos','Jibowu Terminal',             715.0, 23500.00),
    ('Abuja','Utako Terminal','Kano','Kano Main Terminal',           470.0, 18500.00),
    ('Abuja','Utako Terminal','Enugu','Enugu Main Terminal',         480.0, 18000.00),
    -- Ibadan → ...
    ('Ibadan','Iwo Road Terminal','Lagos','Jibowu Terminal',         130.0,  6500.00),
    ('Ibadan','Iwo Road Terminal','Abuja','Utako Terminal',           590.0, 20500.00),
    -- Enugu → ...
    ('Enugu','Enugu Main Terminal','Lagos','Jibowu Terminal',         610.0, 21500.00),
    ('Enugu','Enugu Main Terminal','Port Harcourt','PH Main Terminal', 230.0,  9500.00),
    ('Enugu','Enugu Main Terminal','Abuja','Utako Terminal',          480.0, 18000.00),
    -- Port Harcourt → ...
    ('Port Harcourt','PH Main Terminal','Lagos','Jibowu Terminal',    650.0, 22000.00),
    ('Port Harcourt','PH Main Terminal','Abuja','Utako Terminal',     730.0, 24500.00),
    -- Benin → ...
    ('Benin','Benin Main Terminal','Lagos','Jibowu Terminal',        320.0, 13500.00),
    ('Benin','Benin Main Terminal','Abuja','Utako Terminal',         430.0, 16500.00),
    -- Kano → ...
    ('Kano','Kano Main Terminal','Lagos','Ojota Terminal',           980.0, 28500.00),
    ('Kano','Kano Main Terminal','Abuja','Utako Terminal',           470.0, 18500.00)
) AS d(from_city, from_name, to_city, to_name, km, fare)
WHERE f.city = d.from_city AND f.name = d.from_name
  AND t.city = d.to_city   AND t.name = d.to_name;

-- ---------------------------------------------------------------------------
-- buses  (realistic Nigerian plate numbers —LAG, ABJ, IB, etc.)
-- ---------------------------------------------------------------------------
INSERT INTO bus (plate_number, seat_capacity, model) VALUES
    ('LAG-234-XA', 47, 'Toyota Coaster'),
    ('LAG-456-XB', 35, 'Mitsubishi Rosa'),
    ('LAG-789-XC', 55, 'Yutong ZK6122'),
    ('ABJ-112-XD', 47, 'Toyota Coaster'),
    ('ABJ-223-XE', 55, 'Yutong ZK6122'),
    ('IBD-334-XF', 35, 'Mitsubishi Rosa'),
    ('ENU-445-XG', 47, 'Toyota Coaster'),
    ('PHC-556-XH', 55, 'Yutong ZK6122'),
    ('EDO-667-XJ', 35, 'Mitsubishi Rosa'),
    ('KAN-778-XK', 47, 'Toyota Coaster'),
    ('LAG-889-XL', 55, 'Yutong ZK6122'),
    ('ABJ-990-XM', 35, 'Mitsubishi Rosa'),
    ('LAG-121-XN', 47, 'Toyota Coaster'),
    ('ABJ-232-XP', 47, 'Toyota Coaster'),
    ('KAN-343-XQ', 35, 'Mitsubishi Rosa');

-- ---------------------------------------------------------------------------
-- drivers  (realistic Nigerian names + fictional licence numbers)
-- ---------------------------------------------------------------------------
INSERT INTO driver (full_name, license_no, phone) VALUES
    ('Chinedu Okafor',           'NIG-DL-100001', '+234-803-100-0001'),
    ('Babatunde Adeyemi',        'NIG-DL-100002', '+234-803-100-0002'),
    ('Ibrahim Musa',             'NIG-DL-100003', '+234-803-100-0003'),
    ('Emeka Nwosu',              'NIG-DL-100004', '+234-803-100-0004'),
    ('Sani Bello',               'NIG-DL-100005', '+234-803-100-0005'),
    ('Olumide Bakare',           'NIG-DL-100006', '+234-803-100-0006'),
    ('Uche Eze',                 'NIG-DL-100007', '+234-803-100-0007'),
    ('Abdullahi Mohammed',       'NIG-DL-100008', '+234-803-100-0008'),
    ('Tunde Ogundimu',           'NIG-DL-100009', '+234-803-100-0009'),
    ('Yakubu Aliyu',             'NIG-DL-100010', '+234-803-100-0010'),
    ('Kunle Adesanya',           'NIG-DL-100011', '+234-803-100-0011'),
    ('Joseph Effiong',           'NIG-DL-100012', '+234-803-100-0012'),
    ('Mohammed Suleiman',        'NIG-DL-100013', '+234-803-100-0013'),
    ('Daniel Okonkwo',           'NIG-DL-100014', '+234-803-100-0014'),
    ('Samuel Adeola',            'NIG-DL-100015', '+234-803-100-0015'),
    ('Philip Ezeudu',            'NIG-DL-100016', '+234-803-100-0016'),
    ('Ahmed Tijani',             'NIG-DL-100017', '+234-803-100-0017'),
    ('Tope Aluko',               'NIG-DL-100018', '+234-803-100-0018'),
    ('Bashir Yusuf',             'NIG-DL-100019', '+234-803-100-0019'),
    ('Nnamdi Obi',               'NIG-DL-100020', '+234-803-100-0020');

-- ---------------------------------------------------------------------------
-- passengers  — 60 sample realistic Nigerian names (the bulk generator adds more)
-- ---------------------------------------------------------------------------
INSERT INTO passenger (full_name, phone, email) VALUES
    ('Adebayo Johnson',        '+234-803-200-0001', 'adebayo.johnson@example.com'),
    ('Fatima Ibrahim',         '+234-803-200-0002', 'fatima.ibrahim@example.com'),
    ('Ngozi Eze',              '+234-803-200-0003', 'ngozi.eze@example.com'),
    ('Aisha Mohammed',         '+234-803-200-0004', 'aisha.mohammed@example.com'),
    ('Samuel Okon',            '+234-803-200-0005', 'samuel.okon@example.com'),
    ('Blessing Edo',           '+234-803-200-0006', 'blessing.edo@example.com'),
    ('Tunde Bello',            '+234-803-200-0007', 'tunde.bello@example.com'),
    ('Chioma Obi',             '+234-803-200-0008', 'chioma.obi@example.com'),
    ('Yusuf Adamu',            '+234-803-200-0009', 'yusuf.adamu@example.com'),
    ('Grace Ojo',              '+234-803-200-0010', 'grace.ojo@example.com'),
    ('Femi Oyelaran',          '+234-803-200-0011', 'femi.oyelaran@example.com'),
    ('Hauwa Sani',             '+234-803-200-0012', 'hauwa.sani@example.com'),
    ('Kunle Adewale',          '+234-803-200-0013', 'kunle.adewale@example.com'),
    ('Maryam Bello',           '+234-803-200-0014', 'maryam.bello@example.com'),
    ('Emeka Obiefuna',         '+234-803-200-0015', 'emeka.obiefuna@example.com'),
    ('Hauwa Lawal',            '+234-803-200-0016', 'hauwa.lawal@example.com'),
    ('Oluwaseun Akinola',      '+234-803-200-0017', 'oluwaseun.akinola@example.com'),
    ('Hassan Buba',            '+234-803-200-0018', 'hassan.buba@example.com'),
    ('Lola Coker',             '+234-803-200-0019', 'lola.coker@example.com'),
    ('Ifeanyi Nwokocha',       '+234-803-200-0020', 'ifeanyi.nwokocha@example.com'),
    ('Sekinat Ajao',           '+234-803-200-0021', 'sekinat.ajao@example.com'),
    ('Patrick Effa',           '+234-803-200-0022', 'patrick.effa@example.com'),
    ('Zainab Aliyu',           '+234-803-200-0023', 'zainab.aliyu@example.com'),
    ('Adaeze Nwankwo',         '+234-803-200-0024', 'adaeze.nwankwo@example.com'),
    ('Bukola Oke',             '+234-803-200-0025', 'bukola.oke@example.com'),
    ('Ibrahim Sule',           '+234-803-200-0026', 'ibrahim.sule@example.com'),
    ('Dorcas Eze',             '+234-803-200-0027', 'dorcas.eze@example.com'),
    ('Wale Akinbiyi',          '+234-803-200-0028', 'wale.akinbiyi@example.com'),
    ('Rabiat Mohammed',        '+234-803-200-0029', 'rabiat.mohammed@example.com'),
    ('Chidi Anozie',           '+234-803-200-0030', 'chidi.anozie@example.com'),
    ('Adeyemi Tella',          '+234-803-200-0031', 'adeyemi.tella@example.com'),
    ('Khadija Idris',          '+234-803-200-0032', 'khadija.idris@example.com'),
    ('Gbenga Solarin',         '+234-803-200-0033', 'gbenga.solarin@example.com'),
    ('Rita Uchendu',           '+234-803-200-0034', 'rita.uchendu@example.com'),
    ('Nasir Damaturu',         '+234-803-200-0035', 'nasir.damaturu@example.com'),
    ('Bola Adeyemo',           '+234-803-200-0036', 'bola.adeyemo@example.com'),
    ('Chika Osuala',           '+234-803-200-0037', 'chika.osuala@example.com'),
    ('Aminu Waziri',           '+234-803-200-0038', 'aminu.waziri@example.com'),
    ('Funke Olaniyan',         '+234-803-200-0039', 'funke.olaniyan@example.com'),
    ('Clement Okafor',         '+234-803-200-0040', 'clement.okafor@example.com'),
    ('Hajara Ahmed',           '+234-803-200-0041', 'hajara.ahmed@example.com'),
    ('Nonso Ezeudu',           '+234-803-200-0042', 'nonso.ezeudu@example.com'),
    ('Saheed Bello',           '+234-803-200-0043', 'saheed.bello@example.com'),
    ('Patience Akpan',         '+234-803-200-0044', 'patience.akpan@example.com'),
    ('Idris Lawal',            '+234-803-200-0045', 'idris.lawal@example.com'),
    ('Titilayo Ojo',           '+234-803-200-0046', 'titilayo.ojo@example.com'),
    ('Ekene Onuoha',           '+234-803-200-0047', 'ekene.onuoha@example.com'),
    ('Farida Mohammed',        '+234-803-200-0048', 'farida.mohammed@example.com'),
    ('Adesola Bankole',        '+234-803-200-0049', 'adesola.bankole@example.com'),
    ('Stephen Bawa',           '+234-803-200-0050', 'stephen.bawa@example.com'),
    ('Aisha Tijjani',          '+234-803-200-0051', 'aisha.tijjani@example.com'),
    ('Ebuka Nwafor',           '+234-803-200-0052', 'ebuka.nwafor@example.com'),
    ('Lami Audu',              '+234-803-200-0053', 'lami.audu@example.com'),
    ('Adaeze Obi',             '+234-803-200-0054', 'adaeze.obi@example.com'),
    ('Garba Hassan',           '+234-803-200-0055', 'garba.hassan@example.com'),
    ('Olubunmi Odunsi',        '+234-803-200-0056', 'olubunmi.odunsi@example.com'),
    ('Ahmed Umar',             '+234-803-200-0057', 'ahmed.umar@example.com'),
    ('Joy Eze',                '+234-803-200-0058', 'joy.eze@example.com'),
    ('Murtala Ali',            '+234-803-200-0059', 'murtala.ali@example.com'),
    ('Olaide Bankole',         '+234-803-200-0060', 'olaide.bankole@example.com');

-- ---------------------------------------------------------------------------
-- Trips are NOT seeded here: 04_bulk_generate.py builds every trip (two years
-- of history PLUS the next 14 days of upcoming departures, partly booked), so
-- P2/P3/P5 always have future trips with free seats to work with.
-- (Seeding a few trips here was pointless: the generator TRUNCATEs trip.)
-- ---------------------------------------------------------------------------

-- ---------------------------------------------------------------------------
-- Summary printout
-- ---------------------------------------------------------------------------
SELECT 'terminals'  AS seeded, COUNT(*) AS n FROM terminal
UNION ALL SELECT 'routes',     COUNT(*) FROM route
UNION ALL SELECT 'buses',      COUNT(*) FROM bus
UNION ALL SELECT 'drivers',    COUNT(*) FROM driver
UNION ALL SELECT 'passengers', COUNT(*) FROM passenger;
