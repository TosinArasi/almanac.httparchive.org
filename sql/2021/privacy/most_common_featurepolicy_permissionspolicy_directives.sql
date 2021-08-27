#standardSQL
# Most common directives for Feature-Policy or Permissions-Policy

WITH page_ranks AS (
  SELECT
    client,
    page,
    rank
  FROM
    `httparchive.almanac.summary_response_bodies`
  WHERE
    date = '2021-07-01' AND firstHtml = TRUE
),

response_headers AS (
  SELECT
    client,
    page,
    LOWER(JSON_VALUE(response_header, '$.name')) AS header_name,
    LOWER(JSON_VALUE(response_header, '$.value')) AS header_value
  FROM
    `httparchive.almanac.summary_response_bodies`,
    UNNEST(JSON_QUERY_ARRAY(response_headers)) response_header
  WHERE
    date = '2021-07-01' AND firstHtml = TRUE
),

meta_tags AS (
  SELECT
    client,
    url AS page,
    LOWER(JSON_VALUE(meta_node, '$.http-equiv')) AS tag_name,
    LOWER(JSON_VALUE(meta_node, '$.content')) AS tag_value
  FROM (
    SELECT
      _TABLE_SUFFIX AS client,
      url,
      JSON_VALUE(payload, "$._almanac") AS metrics
    FROM
      `httparchive.pages.2021_07_01_*`
    ),
    UNNEST(JSON_QUERY_ARRAY(metrics, "$.meta-nodes.nodes")) meta_node
  WHERE
    JSON_VALUE(meta_node, '$.http-equiv') IS NOT NULL
),

total_nb_pages AS (
  SELECT
    client,
    rank,
    COUNT(DISTINCT page) AS total_nb_pages
  FROM
    `httparchive.almanac.summary_response_bodies`
  WHERE
    date = '2021-07-01' AND firstHtml = TRUE
  GROUP BY
    1, 2
),

merged_feature_policy AS (
  SELECT
    client,
    page,
    IF(header_name = 'feature-policy', header_value, tag_value) AS feature_policy_value
  FROM
    response_headers FULL OUTER JOIN meta_tags USING (client, page)
  WHERE
    header_name = 'feature-policy' OR tag_name = 'feature-policy'
),

merged_permissions_policy AS (
  SELECT
    client,
    page,
    IF(header_name = 'permissions-policy', header_value, tag_value) AS permissions_policy_value
  FROM
    response_headers FULL OUTER JOIN meta_tags USING (client, page)
  WHERE
    header_name = 'permissions-policy' OR tag_name = 'permissions-policy'
),

feature_policy_directives AS (
  SELECT
    client,
    page,
    ARRAY_AGG(TRIM(SPLIT(TRIM(feature_policy_directive), " ")[OFFSET(0)])) AS directives
  FROM
    merged_feature_policy,
    UNNEST(SPLIT(feature_policy_value, ";")) feature_policy_directive
  GROUP BY
    1, 2
),

permissions_policy_directives AS (
  SELECT
    client,
    page,
    ARRAY_AGG(TRIM(SPLIT(TRIM(permissions_policy_directive), "=")[OFFSET(0)])) AS directives
  FROM
    merged_permissions_policy,
    UNNEST(SPLIT(permissions_policy_value, ",")) permissions_policy_directive
  GROUP BY
    1, 2
),

site_directives AS (
  SELECT
    client,
    page,
    -- distinct directives; https://stackoverflow.com/a/58194837/7391782
    ARRAY(
      SELECT DISTINCT d
      FROM UNNEST(ARRAY_CONCAT(feature_policy_directives.directives, permissions_policy_directives.directives)) d
      WHERE TRIM(d) != ""
      ORDER BY d
    ) AS directives
  FROM
    feature_policy_directives FULL OUTER JOIN permissions_policy_directives USING (client, page)
)

SELECT
  client,
  rank,
  directive,
  COUNT(DISTINCT page) AS nb_websites_with_directive,
  ROUND(COUNT(DISTINCT page) / MIN(total_nb_pages.total_nb_pages), 2) AS pct_websites_with_directive
FROM
  site_directives JOIN page_ranks USING (client, page) JOIN total_nb_pages USING (client, rank),
  UNNEST(site_directives.directives) directive
GROUP BY
  1, 2, 3
ORDER BY
  2 ASC, 1 ASC, 4 DESC, 3 ASC
