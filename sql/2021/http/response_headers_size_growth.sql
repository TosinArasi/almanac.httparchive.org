#standardSQL
SELECT
  REGEXP_REPLACE(_TABLE_SUFFIX, r'(\d+)_(\d+)_(\d+).*', r'\1-\2-\3') AS date,
  IF(ENDS_WITH(_TABLE_SUFFIX, 'desktop'), 'desktop', 'mobile') AS client,
  ROUND(APPROX_QUANTILES(respHeadersSize, 1000)[OFFSET(100)] / 1024, 2) AS p10,
  ROUND(APPROX_QUANTILES(respHeadersSize, 1000)[OFFSET(250)] / 1024, 2) AS p25,
  ROUND(APPROX_QUANTILES(respHeadersSize, 1000)[OFFSET(500)] / 1024, 2) AS p50,
  ROUND(APPROX_QUANTILES(respHeadersSize, 1000)[OFFSET(750)] / 1024, 2) AS p75,
  ROUND(APPROX_QUANTILES(respHeadersSize, 1000)[OFFSET(900)] / 1024, 2) AS p90,
  ROUND(APPROX_QUANTILES(respHeadersSize, 1000)[OFFSET(1000)] / 1024, 2) AS p100
FROM
  `httparchive.summary_requests.*`,
  UNNEST([10, 25, 50, 75, 90, 100]) AS percentile
WHERE
  respHeadersSize IS NOT NULL
GROUP BY
  date,
  client
ORDER BY
  date ASC,
  client
