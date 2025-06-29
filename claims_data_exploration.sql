-- CREATE TABLE STRUCTURE FOR DATA IMPORT --
CREATE TABLE public.fake_claims_data
(
    claim_id text,
    provider_npi numeric,
    patient_id text,
    date_of_service date,
    billed_amount numeric,
    allowed_amount numeric,
    paid_amount numeric,
    diagnosis_code text,
    procedure_code text,
    insurance_type text,
    claim_status text,
    denial_reason text
);

ALTER TABLE IF EXISTS public.fake_claims_data
    OWNER to postgres;

-- CREATE A COPY TO PRESERVE ORIGINAL DATA --

CREATE TABLE fake_claims_data_COPY AS
SELECT * FROM fake_claims_data;

SELECT *
FROM fake_claims_data_COPY;

-- DUPLICATE ROW CHECK (using claim_id) --

SELECT *
FROM fake_claims_data_COPY
WHERE claim_id IN (
	SELECT claim_id
	FROM fake_claims_data_COPY
	GROUP BY claim_id
	HAVING COUNT(*) > 1
);

-- NULL / EMPTY STRING CHECK -- 

SELECT *
FROM fake_claims_data_COPY
WHERE claim_id is NULL OR claim_id = ''

SELECT *
FROM fake_claims_data_COPY
WHERE provider_npi is NULL;

SELECT *
FROM fake_claims_data_COPY
WHERE patient_id is NULL OR patient_id = '';

SELECT *
FROM fake_claims_data_COPY
WHERE date_of_service is NULL;

SELECT *
FROM fake_claims_data_COPY
WHERE billed_amount is NULL;

SELECT *
FROM fake_claims_data_COPY
WHERE allowed_amount is NULL;

SELECT *
FROM fake_claims_data_COPY
WHERE paid_amount is NULL;

SELECT *
FROM fake_claims_data_COPY
WHERE diagnosis_code is NULL OR diagnosis_code = '';

SELECT *
FROM fake_claims_data_COPY
WHERE procedure_code is NULL OR procedure_code = '';

SELECT *
FROM fake_claims_data_COPY
WHERE insurance_type is NULL OR insurance_type = '';

SELECT *
FROM fake_claims_data_COPY
WHERE claim_status is NULL OR claim_status = '';

SELECT *
FROM fake_claims_data_COPY
WHERE denial_reason is NULL OR denial_reason = '';

UPDATE fake_claims_data_COPY
SET denial_reason = COALESCE(denial_reason, 'NA');

-- STANDARDIZE DATA -- 

SELECT *
FROM fake_claims_data_COPY
WHERE LENGTH(claim_id) != 10 OR claim_id !~ '^[A-Z0-9]+$';

SELECT *
FROM fake_claims_data_COPY
WHERE LENGTH(provider_npi::TEXT) != 10;

SELECT *
FROM fake_claims_data_COPY
WHERE LENGTH(patient_id) != 10 OR patient_id !~ '^[A-Z]{2}[0-9]{8}$';

SELECT *
FROM fake_claims_data_COPY
WHERE date_of_service::TEXT !~ '^\d{4}-(0[1-9]|1[0-2])-(0[1-9]|[12][0-9]|3[01])$';

SELECT *
FROM fake_claims_data_COPY
WHERE billed_amount < 0 OR billed_amount::TEXT !~ '^\d+\.\d{2}$'; -- amount must have two decimal places

UPDATE fake_claims_data_COPY
SET billed_amount = ROUND(billed_amount, 2);

SELECT *
FROM fake_claims_data_COPY
WHERE allowed_amount < 0 OR allowed_amount::TEXT !~ '^\d+\.\d{2}$'; 

UPDATE fake_claims_data_COPY
SET allowed_amount = ROUND(allowed_amount, 2);

SELECT *
FROM fake_claims_data_COPY
WHERE allowed_amount > billed_amount; -- allowed can't be greater than billed

SELECT *
FROM fake_claims_data_COPY
WHERE paid_amount < 0 OR paid_amount::TEXT !~ '^\d+\.\d{2}$';

UPDATE fake_claims_data_COPY
SET paid_amount = ROUND(paid_amount, 2);

SELECT *
FROM fake_claims_data_COPY
WHERE paid_amount > allowed_amount; -- paid can't be greater than allowed

SELECT *
FROM fake_claims_data_COPY
WHERE LENGTH(procedure_code::TEXT) != 5;

SELECT *
FROM fake_claims_data_COPY
WHERE insurance_type NOT IN ('Medicaid', 'Medicare','Commercial', 'Self-Pay');

SELECT *
FROM fake_claims_data_COPY
WHERE claim_status NOT IN ('Paid', 'Denied', 'Pending');

SELECT *
FROM fake_claims_data_COPY
WHERE denial_reason NOT IN ('Duplicate Claim', 'Pre-Existing Condition', 'Missing Documentation', 'Out-of-Network', 'Service Not Covered', 'NA');

SELECT *
FROM fake_claims_data_COPY
WHERE claim_status != 'Denied' AND denial_reason != 'NA'; -- paid or pending claims cannot have a denial reason

SELECT *
FROM fake_claims_data_COPY
WHERE claim_status = 'Denied' AND denial_reason = 'NA'; -- denied claims must have a denial reason

-- DATA EXPLORATION --

-- What does the monthly claim count breakdown look like for each year? 
SELECT
	EXTRACT(YEAR FROM date_of_service) AS year,
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) = 1 THEN 1 END) AS jan,
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) = 2 THEN 1 END) AS feb,
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) = 3 THEN 1 END) AS mar,
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) = 4 THEN 1 END) AS apr,
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) = 5 THEN 1 END) AS may,
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) = 6 THEN 1 END) AS jun,
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) = 7 THEN 1 END) AS jul,
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) = 8 THEN 1 END) AS aug,
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) = 9 THEN 1 END) AS sep,
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) = 10 THEN 1 END) AS oct,
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) = 11 THEN 1 END) AS nov,
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) = 12 THEN 1 END) AS dec,
	COUNT(*) total
FROM fake_claims_data_COPY
GROUP BY EXTRACT(YEAR FROM date_of_service)
ORDER BY year; 

-- What are the denial rates of each insurance type? What are the most common reasons for denial for each insurance type?
SELECT 
    insurance_type,
	COUNT(*) AS total_claim_count,
    COUNT(*) FILTER (WHERE claim_status = 'Denied') AS denied_count,
	ROUND(COUNT(*) FILTER (WHERE claim_status = 'Denied') * 100.0 / NULLIF(COUNT(*), 0), 1) AS denied_percent,
	ROUND(COUNT(*) FILTER (WHERE claim_status = 'Denied' AND denial_reason = 'Service Not Covered') * 100.0 / NULLIF(COUNT(*), 0), 1) AS not_covered_percent,
	ROUND(COUNT(*) FILTER (WHERE claim_status = 'Denied' AND denial_reason = 'Missing Documentation') * 100.0 / NULLIF(COUNT(*), 0), 1) AS missing_docs_percent,
	ROUND(COUNT(*) FILTER (WHERE claim_status = 'Denied' AND denial_reason = 'Duplicate Claim') * 100.0 / NULLIF(COUNT(*), 0), 1) AS duplicate_claim_percent,
	ROUND(COUNT(*) FILTER (WHERE claim_status = 'Denied' AND denial_reason = 'Pre-Existing Condition') * 100.0 / NULLIF(COUNT(*), 0), 1) AS pre_existing_cond_percent,
	ROUND(COUNT(*) FILTER (WHERE claim_status = 'Denied' AND denial_reason = 'Out-of-Network') * 100.0 / NULLIF(COUNT(*), 0), 1) AS out_of_network_percent
FROM fake_claims_data_COPY
GROUP BY insurance_type
ORDER BY denied_percent DESC; 

-- Is average insurance payout ratio increasing or decreasing each year for each insurance type?
SELECT 
	insurance_type,
	ROUND(AVG(CASE WHEN EXTRACT(YEAR FROM date_of_service) = 2020 THEN paid_amount / allowed_amount * 100.0 END), 1) AS "avg_percent_paid_2020",
	ROUND(AVG(CASE WHEN EXTRACT(YEAR FROM date_of_service) = 2021 THEN paid_amount / allowed_amount * 100.0 END), 1) AS "avg_percent_paid_2021",
	ROUND(AVG(CASE WHEN EXTRACT(YEAR FROM date_of_service) = 2022 THEN paid_amount / allowed_amount * 100.0 END), 1) AS "avg_percent_paid_2022",
	ROUND(AVG(CASE WHEN EXTRACT(YEAR FROM date_of_service) = 2023 THEN paid_amount / allowed_amount * 100.0 END), 1) AS "avg_percent_paid_2023",
	ROUND(AVG(CASE WHEN EXTRACT(YEAR FROM date_of_service) = 2024 THEN paid_amount / allowed_amount * 100.0 END), 1) AS "avg_percent_paid_2024"
FROM fake_claims_data_COPY
GROUP BY insurance_type; 

-- What is the denial rate and most common denial reason for each procedure code?
WITH denial_rates AS(
	SELECT
	    procedure_code,
	    total_claim_count,
	    denied_claim_count,
	    ROUND(denied_claim_count::numeric / total_claim_count * 100.0, 2) AS denial_rate
	FROM (
	    SELECT
	        procedure_code,
	        COUNT(*) AS total_claim_count,
	        COUNT(*) FILTER (WHERE claim_status = 'Denied') AS denied_claim_count
	    FROM fake_claims_data_COPY
		WHERE provider_npi = '3904283765' -- NPIs: 3904283765, 2021349671, 4957261083, 5863514709, 1739201857
	    GROUP BY procedure_code
	 ) AS sub
),
ranked_denial_reasons AS (
  SELECT
    procedure_code,
    denial_reason,
	ROW_NUMBER() OVER (
      PARTITION BY procedure_code
      ORDER BY COUNT(*) DESC
    ) AS reason_rank,
    COUNT(*) AS reason_count_total,
	COUNT(*) FILTER (WHERE insurance_type = 'Medicare') AS medicare_count,
    COUNT(*) FILTER (WHERE insurance_type = 'Medicaid') AS medicaid_count,
    COUNT(*) FILTER (WHERE insurance_type = 'Commercial') AS commercial_count,
		COUNT(*) FILTER (WHERE insurance_type = 'Self-Pay') AS self_pay_count
  FROM fake_claims_data_COPY
  WHERE claim_status = 'Denied' AND provider_npi = '3904283765'
  GROUP BY procedure_code, denial_reason
)
SELECT
  d.procedure_code,
  d.total_claim_count,
  d.denied_claim_count,
  d.denial_rate,
  r.denial_reason AS top_denial_reason,
  r.reason_count_total,
  r.medicare_count,
  r.medicaid_count,
  r.commercial_count,
  r.self_pay_count
FROM denial_rates d
LEFT JOIN ranked_denial_reasons r
  ON d.procedure_code = r.procedure_code AND r.reason_rank = 1
ORDER BY d.denial_rate DESC;

-- Procedure code money related averages (for specified provider).
SELECT 
	procedure_code,
	ROUND(AVG(billed_amount), 2) AS avg_billed_amount,
	ROUND(AVG(allowed_amount), 2) AS avg_allowed_amount,
	ROUND(AVG(paid_amount), 2) AS avg_paid_amount,
	ROUND(AVG(paid_amount) / AVG(allowed_amount) * 100.0, 1) AS avg_percent_paid
FROM fake_claims_data_COPY
WHERE provider_npi = '3904283765' -- NPIs: 3904283765, 2021349671, 4957261083, 5863514709, 1739201857
GROUP BY procedure_code
ORDER BY avg_percent_paid DESC;

-- Which is the most common insurance type taken by each provider? Least common?
SELECT 
	provider_npi,
	COUNT(CASE WHEN insurance_type = 'Medicaid' THEN 1 END) AS "medicaid_count",
	COUNT(CASE WHEN insurance_type = 'Medicare' THEN 1 END) AS "medicare_count",
	COUNT(CASE WHEN insurance_type = 'Commercial' THEN 1 END) AS "commercial_count",
	COUNT(CASE WHEN insurance_type = 'Self-Pay' THEN 1 END) AS "selfpay_count"
FROM fake_claims_data_COPY
GROUP BY provider_npi; 

-- Running total for paid amounts for a specified year and provider.
SELECT 
	claim_id,
	provider_npi,
	date_of_service,
	paid_amount,
	SUM(CASE WHEN claim_status NOT IN ('Denied', 'Pending') THEN paid_amount ELSE 0 END) OVER (
		PARTITION BY provider_npi
		ORDER BY
			EXTRACT(YEAR FROM date_of_service),
			date_of_service
	) AS running_total_paid
FROM fake_claims_data_COPY
WHERE claim_status NOT IN ('Denied', 'Pending') 
	AND provider_npi = '3904283765' -- NPIs: 3904283765, 2021349671, 4957261083, 5863514709, 1739201857
	AND EXTRACT(YEAR FROM date_of_service) = 2020 -- replace with desired year (2020-2024)
ORDER BY
	provider_npi,
	date_of_service; 

-- Which season of the year has the highest patient traffic (grouped by provider)? How about the lowest?
SELECT 
	provider_npi,
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) IN (12, 1, 2) THEN 1 END) AS "winter_claim_count",
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) IN (3, 4, 5) THEN 1 END) AS "spring_claim_count",
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) IN (6, 7, 8) THEN 1 END) AS "summer_claim_count",
	COUNT(CASE WHEN EXTRACT(MONTH FROM date_of_service) IN (9, 10, 11) THEN 1 END) AS "fall_claim_count"
FROM fake_claims_data_COPY
GROUP BY provider_npi; 


