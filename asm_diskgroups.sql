SET LINESIZE 150
SET PAGESIZE 9999
SET VERIFY off
COLUMN group_name FORMAT a25 HEAD 'DISKGROUP_NAME'
COLUMN state FORMAT a11 HEAD 'STATE'
COLUMN type FORMAT a6 HEAD 'TYPE'
COLUMN total_mb FORMAT 999,999,999 HEAD 'TOTAL SIZE(GB)'
COLUMN free_mb FORMAT 999,999,999 HEAD 'FREE SIZE (GB)'
COLUMN used_mb FORMAT 999,999,999 HEAD 'USED SIZE (GB)'
COLUMN pct_used FORMAT 999.99 HEAD 'PERCENTAGE USED'

SELECT distinct name group_name, 
state state, 
type type,
round(total_mb/1024) TOTAL_GB , round(free_mb/1024) free_gb ,
round((total_mb - free_mb) / 1024) used_gb ,
round((1- (free_mb / total_mb))*100, 2) pct_used 
from v$asm_diskgroup;