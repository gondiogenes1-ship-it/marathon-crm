import fs from 'node:fs/promises';
import {spawnSync} from 'node:child_process';
import assert from 'node:assert/strict';
import {buildPatientReportWorkbook,patientReportSheets} from '../public/patient-report-workbook.js';
const out=new URL('../.report-validation/',import.meta.url);await fs.mkdir(out,{recursive:true});
const query="set request.jwt.claim.sub='00000000-0000-4000-8000-000000009901';select public.marathon_patient_dashboard('{\"from\":\"2026-11-01\",\"to\":\"2026-11-05\",\"sede\":\"\",\"specialty\":\"\",\"therapy\":\"\",\"professional\":\"\"}'::jsonb);";
const result=spawnSync('C:/Program Files/PostgreSQL/18/bin/psql.exe',['-w','-h','127.0.0.1','-p','55439','-U','postgres','-d','marathon_saldo_demo_20261104','-qAt','-v','ON_ERROR_STOP=1','-f','-'],{input:query,encoding:'utf8',windowsHide:true,env:{...process.env,PGCLIENTENCODING:'UTF8'}});
if(result.status!==0)throw Error(result.stderr);
const report=JSON.parse(result.stdout.trim());await fs.writeFile(new URL('datos-demo.json',out),JSON.stringify(report,null,2));
assert.equal(patientReportSheets(report).length,5);
for(const tab of [null,'overview','activity','agenda','profile','quality']){const bytes=buildPatientReportWorkbook(report,{tab});assert(bytes.length>1000);await fs.writeFile(new URL((tab||'completo')+'.xlsx',out),bytes);}
const empty=structuredClone(report);empty.groups=[];empty.trend=[];empty.coverage=[];empty.capacity.rows=[];empty.waiting.rows=[];empty.flow=[];empty.summary.attendance=null;empty.summary.frequency=null;empty.waiting.median_days=null;
for(const key of Object.keys(empty.summary))empty.summary[key]=['attendance','frequency','completeness'].includes(key)?null:0;
Object.assign(empty.firsts,{observed:0,returning:0,first_site:null,first_specialty:null});Object.assign(empty.capacity,{available:0,reserved:0,effective:0,reserved_pct:null,effective_pct:null});Object.assign(empty.waiting,{requests:0,patients:0,linked_count:0,linked_median_days:null});Object.assign(empty.quality,{missing_coverage:0,future:0});
await fs.writeFile(new URL('sin-datos.xlsx',out),buildPatientReportWorkbook(empty));
const special=structuredClone(report);special.groups.push({kind:'specialty',label:'=HYPERLINK("https://example.invalid") <texto> & acentos',patients:1,present:1,absent:0,pending:0,cancelled:0,attendance:null});await fs.writeFile(new URL('texto-seguro.xlsx',out),buildPatientReportWorkbook(special));
assert.throws(()=>buildPatientReportWorkbook(report,{tab:'no-existe'}));
console.log('PASS: 5 pestañas, archivo completo, datos vacíos, texto literal y pestaña inválida.');
