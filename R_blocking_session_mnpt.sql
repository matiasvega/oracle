SET FEEDBACK OFF
set serveroutput ON FORMAT WORD_WRAPPED
spool /tmp/main.sql 

--- change the path to create main file.
set linesize 5000
DECLARE

 c_sid  NUMBER := $sid;
 c_blocking NUMBER := $blocking_session;
 c_sql_id varchar2(100) := '$sql_id';
 v_sql_spool VARCHAR2(100);
 v_awr_spool varchar2(200);
 v_xplan_spool varchar2(200); 

CURSOR c_snapid(l_sid number, l_blocking number, l_sqlid varchar2) IS
select dbid,instance_number,min(snap_id) as start_snap_id,min(snap_id)+2 as end_snap_id,session_id,blocking_session,sql_id
from dba_hist_active_sess_history 
   where session_id=l_sid	and blocking_session=l_blocking and sql_id=l_sqlid group by session_id,blocking_session,sql_id,dbid,instance_number ;
				

CURSOR c_sqlid(l_sid number, l_blocking number, l_sqlid varchar2) IS
with tsp as (
select  min (sample_time) as start_sample, max (sample_time) as end_sample ,   SUBSTR (MAX (sample_time) - MIN (sample_time),
                 INSTR (MAX (sample_time) - MIN (sample_time), ' ') 
                ) AS RUN_TIME,session_id,SESSION_SERIAL#,user_id from dba_hist_active_sess_history where session_id=l_sid	and blocking_session=l_blocking and sql_id=l_sqlid--and session_serial#=4936
group by session_id,SESSION_SERIAL#,user_id order by min(sample_time) desc)
,tsp1 as (
select distinct b.session_id, b.session_serial#,b.blocking_session, b.blocking_session_serial#  from tsp a, dba_hist_active_sess_history b
where  b.sample_time between a.start_sample and a.end_sample
and b.event='enq: TX - row lock contention'),
tsp3 as (
select a.*, b.sql_text from ( select distinct k.session_id,k.sample_time, k.sql_id, k.SQL_CHILD_NUMBER
from dba_hist_active_sess_history k,tsp a
where k.session_id in (select distinct c.session_id  from tsp1 c
                    union all
                    select distinct c.blocking_session from tsp1 c) and k.sample_time between a.start_sample and a.end_sample )  a, dba_hist_sqltext b
where a.sql_id=b.sql_id
order by 1,2)
select min(sample_time),max(sample_time),session_id,sql_id from tsp3 group by session_id,sql_id order by 3;

 c_single c_sqlid%rowtype;
 
 c_awrrepo  c_snapid%rowtype;
 
BEGIN
dbms_output.enable(1000000);

BEGIN

dbms_output.put_line(chr(10)); 

dbms_output.put_line('-- blocking_session_details.csv report pull ');

   dbms_output.put_line('set verify off lines 3000 trimspool on heading on '||chr(10)
 ||'set colsep '
 ||chr(39)
 ||','
 ||chr(39)
 ||chr(10)
 ||'spool /tmp/blocking_session_details.csv'
 ||chr(10)
 ||' with tsp as (
select  min (sample_time) as start_sample, max (sample_time) as end_sample ,   SUBSTR (MAX (sample_time) - MIN (sample_time),
                 INSTR (MAX (sample_time) - MIN (sample_time), '||chr(39)||' '||chr(39)||') 
                ) AS RUN_TIME,session_id,SESSION_SERIAL#,user_id from dba_hist_active_sess_history where 
				session_id='||c_sid||' and blocking_session='||c_blocking||' and sql_id='||chr(39)||c_sql_id||chr(39)||'--and session_serial#=4936
group by session_id,SESSION_SERIAL#,user_id order by min(sample_time) desc)
select distinct b.session_id, b.session_serial#,b.blocking_session, b.blocking_session_serial#  from tsp a, dba_hist_active_sess_history b
where  b.sample_time between a.start_sample and a.end_sample
and b.event='
||chr(39)
||'enq: TX - row lock contention'
||chr(39)||';'
 ||chr(10)
 ||'spool off'); 
 
   dbms_output.put_line(chr(10));
   
dbms_output.put_line('-- blocking_sqls_details.csv report pull ');

dbms_output.put_line('set verify off trimspool on long 1000000 longchunksize 1000000  linesize 20000 pages 0 wrap off heading on '||chr(10)
 ||'set colsep '
 ||chr(39)
 ||','
 ||chr(39)
 ||chr(10)
 ||'COLUMN sql_text WORD_WRAPPED'
 ||chr(10)
 ||'spool /tmp/blocking_sqls_details.csv'
 ||chr(10)
 ||' with tsp as (
select  min (sample_time) as start_sample, max (sample_time) as end_sample ,   SUBSTR (MAX (sample_time) - MIN (sample_time),
                 INSTR (MAX (sample_time) - MIN (sample_time), '||chr(39)||' '||chr(39)||') 
                ) AS RUN_TIME,session_id,SESSION_SERIAL#,user_id from dba_hist_active_sess_history where 
				session_id='||c_sid||' and blocking_session='||c_blocking||' and sql_id='||chr(39)||c_sql_id||chr(39)||'--and session_serial#=4936
group by session_id,SESSION_SERIAL#,user_id order by min(sample_time) desc),
tsp1 as (select distinct b.session_id, b.session_serial#,b.blocking_session, b.blocking_session_serial#  from tsp a, dba_hist_active_sess_history b
where  b.sample_time between a.start_sample and a.end_sample
and b.event='
||chr(39)
||'enq: TX - row lock contention'
||chr(39)||')'
||chr(10)
||'select a.*, b.sql_text from ( select distinct k.session_id,k.sample_time, k.sql_id, k.SQL_CHILD_NUMBER
from dba_hist_active_sess_history k,tsp a
where k.session_id in (select distinct c.session_id  from tsp1 c
                    union all
                    select distinct c.blocking_session from tsp1 c) and k.sample_time between a.start_sample and a.end_sample )  a, dba_hist_sqltext b
where a.sql_id=b.sql_id
order by 1,2;'
 ||chr(10)
 ||'spool off');
 
  dbms_output.put_line(chr(10));
  
END;
   

BEGIN

dbms_output.put_line('-- AWR Report Generation for the 30 min blocking period ');

 open c_snapid(c_sid,c_blocking,c_sql_id);
 LOOP
  FETCH c_snapid INTO c_awrrepo;
   EXIT WHEN c_snapid%notfound;
  
 -- Construct filename for AWR report
 v_awr_spool := ''||trim(c_awrrepo.session_id)||'_'||c_awrrepo.sql_id||'_awr_report.html';
 
-- dbms_output.put_line('set heading off feedback off lines 800 pages 5000 trimspool on trimout on');
 
 dbms_output.put_line('set heading off feedback off lines 800 pages 5000 trimspool on trimout on '
 ||chr(10)
 ||'spool /tmp/'||v_awr_spool
 ||chr(10)
 ||' select output from table(dbms_workload_repository.awr_report_html('
 ||c_awrrepo.dbid||','||c_awrrepo.instance_number||','||c_awrrepo.start_snap_id||','||c_awrrepo.end_snap_id||',0));'
 ||chr(10)
 ||'spool off');
 
  dbms_output.put_line(chr(10));
 

 END LOOP;
 
 CLOSE c_snapid;
 
 END;

dbms_output.put_line('-- Bind variable and Xplan Report Generation for the Blocking SQLs ');


open c_sqlid(c_sid,c_blocking,c_sql_id);
 LOOP
  FETCH c_sqlid INTO c_single;
  EXIT WHEN c_sqlid%notfound;
  
 -- Construct filename for AWR report
 v_sql_spool := 'bind_'||trim(c_single.session_id)||'_'||c_single.sql_id||'.csv';
 
 dbms_output.put_line('set verify off lines 15000 trimspool on heading on '||chr(10)
 || 'set colsep '
 ||chr(39)
 ||','
 ||chr(39)
 ||chr(10)
 ||'spool /tmp/'||v_sql_spool
 ||chr(10)
 ||' SELECT * FROM v$sql_bind_capture WHERE sql_id='
 ||chr(39) 
 ||c_single.sql_id
 ||chr(39)||' order by child_number; '
 ||chr(10)
 ||'spool off');
 
  dbms_output.put_line(chr(10));
  
   v_xplan_spool := 'Xplan_'||trim(c_single.session_id)||'_'||c_single.sql_id||'.txt';

dbms_output.put_line('set heading off feedback off lines 800 pages 5000 trimspool on trimout on '
 ||chr(10)
 ||'spool /tmp/'||v_xplan_spool
 ||chr(10)
 ||'select * from table(dbms_xplan.display_awr ('
 ||chr(39)
 ||c_single.sql_id
 ||chr(39)
 ||', format => '||chr(39)||'TYPICAL +PEEKED_BINDS'||chr(39)||'));'
 ||chr(10)
||'spool off');

dbms_output.put_line(chr(10)); 
 
 END LOOP;
 
 CLOSE c_sqlid;
 
END;
/
 
spool off

select sysdate from dual;
@/tmp/main.sql
