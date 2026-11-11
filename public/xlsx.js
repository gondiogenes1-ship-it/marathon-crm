// Exportador original Marathon conservado, sin dependencias externas.
export const BillingXlsx=(()=>{
  const encode=s=>new TextEncoder().encode(s);
  const xml=s=>String(s??'').replace(/[\u0000-\u0008\u000b\u000c\u000e-\u001f]/g,'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&apos;'}[c]));
  const crcTable=Array.from({length:256},(_,i)=>{let c=i;for(let n=0;n<8;n++)c=c&1?0xedb88320^(c>>>1):c>>>1;return c>>>0;});
  const crc=bytes=>{let c=0xffffffff;for(const b of bytes)c=crcTable[(c^b)&255]^(c>>>8);return (c^0xffffffff)>>>0;};
  const concat=parts=>{const out=new Uint8Array(parts.reduce((n,p)=>n+p.length,0));let at=0;for(const p of parts){out.set(p,at);at+=p.length;}return out;};
  function zip(files){
    const parts=[],central=[];let offset=0;
    for(const [path,text] of Object.entries(files)){
      const name=encode(path),data=encode(text),sum=crc(data),head=new Uint8Array(30),v=new DataView(head.buffer);
      v.setUint32(0,0x04034b50,true);v.setUint16(4,20,true);v.setUint16(6,0x800,true);v.setUint16(12,33,true);v.setUint32(14,sum,true);v.setUint32(18,data.length,true);v.setUint32(22,data.length,true);v.setUint16(26,name.length,true);
      parts.push(head,name,data);
      const dir=new Uint8Array(46),d=new DataView(dir.buffer);d.setUint32(0,0x02014b50,true);d.setUint16(4,20,true);d.setUint16(6,20,true);d.setUint16(8,0x800,true);d.setUint16(14,33,true);d.setUint32(16,sum,true);d.setUint32(20,data.length,true);d.setUint32(24,data.length,true);d.setUint16(28,name.length,true);d.setUint32(42,offset,true);central.push(dir,name);offset+=head.length+name.length+data.length;
    }
    const cd=concat(central),end=new Uint8Array(22),v=new DataView(end.buffer),count=Object.keys(files).length;
    v.setUint32(0,0x06054b50,true);v.setUint16(8,count,true);v.setUint16(10,count,true);v.setUint32(12,cd.length,true);v.setUint32(16,offset,true);return concat([...parts,cd,end]);
  }
  const workbookStyles=`<?xml version="1.0" encoding="UTF-8"?><styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><fonts count="3"><font><sz val="11"/><name val="Calibri"/></font><font><b/><color rgb="FFFFFFFF"/><sz val="11"/><name val="Calibri"/></font><font><b/><sz val="14"/><name val="Calibri"/></font></fonts><fills count="4"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF016237"/><bgColor indexed="64"/></patternFill></fill><fill><patternFill patternType="solid"><fgColor rgb="FFEAF1EC"/><bgColor indexed="64"/></patternFill></fill></fills><borders count="1"><border><left/><right/><top/><bottom/><diagonal/></border></borders><cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs><cellXfs count="7"><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="1" fillId="2" borderId="0" xfId="0" applyAlignment="1"><alignment vertical="center" wrapText="1"/></xf><xf numFmtId="1" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment horizontal="center" vertical="center"/></xf><xf numFmtId="49" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/><xf numFmtId="0" fontId="2" fillId="0" borderId="0" xfId="0"/><xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0" applyAlignment="1"><alignment wrapText="1" vertical="center"/></xf><xf numFmtId="1" fontId="2" fillId="3" borderId="0" xfId="0"/></cellXfs><cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles></styleSheet>`;
  function packageWorkbook(sheet,styles,sheetName){
    const files={'[Content_Types].xml':'<?xml version="1.0" encoding="UTF-8"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>',
      '_rels/.rels':'<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>',
      'xl/workbook.xml':'<?xml version="1.0" encoding="UTF-8"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Facturacion" sheetId="1" r:id="rId1"/></sheets></workbook>',
      'xl/_rels/workbook.xml.rels':'<?xml version="1.0" encoding="UTF-8"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>',
      'xl/styles.xml':styles,'xl/worksheets/sheet1.xml':sheet};
    files['xl/workbook.xml']=files['xl/workbook.xml'].replace('name="Facturacion"','name="'+xml(sheetName)+'"');
    return zip(files);
  }
  function build(report){
    if(!report.valid||!report.rows.length)throw new Error('Elegí los filtros y generá un resumen con pacientes antes de descargar.');
    if(report.rows.length>1048567)throw new Error('El resumen supera el límite de filas de Excel. Reducí los filtros.');
    const columns=['Nombre','Apellido','Número de afiliado','Sesiones realizadas en '+report.period.label,'Cantidad pendiente en '+report.period.nextLabel],rows=[];
    const cell=(r,col,value,style)=>{const ref=String.fromCharCode(65+col)+r;return typeof value==='number'?`<c r="${ref}" s="${style}"><v>${value}</v></c>`:`<c r="${ref}" t="inlineStr" s="${style}"><is><t xml:space="preserve">${xml(value)}</t></is></c>`;};
    const row=(r,values,style=0,height=22)=>`<row r="${r}" ht="${height}" customHeight="1">${values.map((v,c)=>cell(r,c,v,typeof style==='function'?style(c):style)).join('')}</row>`;
    rows.push(row(1,['Facturación de obras sociales'],4,28),row(2,['Obra social',report.os]),row(3,['Terapia',report.therapy]),row(4,['Sede',report.sede]),row(5,['Presente en '+report.period.label+'; Pendiente agendado en '+report.period.nextLabel+'. Ficha actual y base activa.'],5,34),row(7,columns,1,48));
    report.rows.forEach((r,i)=>rows.push(row(i+8,[r.name,r.surname,r.affiliate,r.done,r.next],c=>c>=3?2:3)));
    const last=report.rows.length+7,total=last+1;rows.push(row(total,['TOTAL','','',report.done,report.next],6,25));
    const sheet=`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetPr><pageSetUpPr fitToPage="1"/></sheetPr><dimension ref="A1:E${total}"/><sheetViews><sheetView workbookViewId="0"><pane ySplit="7" topLeftCell="A8" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="22"/><cols><col min="1" max="2" width="25" customWidth="1"/><col min="3" max="3" width="24" customWidth="1"/><col min="4" max="5" width="29" customWidth="1"/></cols><sheetData>${rows.join('')}</sheetData><autoFilter ref="A7:E${last}"/><mergeCells count="2"><mergeCell ref="A1:E1"/><mergeCell ref="A5:E5"/></mergeCells><pageMargins left="0.3" right="0.3" top="0.5" bottom="0.5" header="0.2" footer="0.2"/><pageSetup orientation="landscape" paperSize="9" fitToWidth="1" fitToHeight="0"/></worksheet>`;
    const styles=workbookStyles;
    return packageWorkbook(sheet,styles,'Facturacion');
  }
  function buildGrid(config){
    const columns=config.columns,records=config.rows;
    if(!Array.isArray(columns)||!columns.length||columns.length>16384||!Array.isArray(records)||!records.length)throw new Error('No hay datos para exportar.');
    if(records.length>1048569)throw new Error('El archivo supera el límite de filas de Excel. Reducí los filtros.');
    const letter=index=>{let name='';for(let n=index+1;n>0;n=Math.floor((n-1)/26))name=String.fromCharCode(65+(n-1)%26)+name;return name;};
    const cell=(r,c,value,style)=>{const ref=letter(c)+r;if(typeof value==='number'){if(!Number.isFinite(value))throw new Error('Hay una cantidad inválida en el stock. Revisá los datos antes de exportar.');return `<c r="${ref}" s="${style}"><v>${value}</v></c>`;}return `<c r="${ref}" t="inlineStr" s="${style}"><is><t xml:space="preserve">${xml(value)}</t></is></c>`;};
    const row=(r,values,style,height=22)=>`<row r="${r}" ht="${height}" customHeight="1">${values.map((v,c)=>cell(r,c,v,typeof style==='function'?style(c):style)).join('')}</row>`;
    const rows=[row(1,[config.title||'Reporte'],4,28)];
    (config.metadata||[]).slice(0,3).forEach((values,i)=>rows.push(row(i+2,values,0)));
    rows.push(row(5,[config.note||''],5,34),row(7,columns.map(c=>c.name),1,45));
    records.forEach((values,i)=>{
      const height=Math.max(22,Math.min(200,15*Math.max(...values.map((v,c)=>Math.ceil(String(v??'').length/(columns[c]?.width||20))))));
      rows.push(row(i+8,values,c=>columns[c]?.numeric?2:5,height));
    });
    const last=records.length+7,endColumn=letter(columns.length-1);
    const cols=columns.map((c,i)=>`<col min="${i+1}" max="${i+1}" width="${Math.max(8,Math.min(80,Number(c.width)||20))}" customWidth="1"/>`).join('');
    const sheet=`<?xml version="1.0" encoding="UTF-8" standalone="yes"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetPr><pageSetUpPr fitToPage="1"/></sheetPr><dimension ref="A1:${endColumn}${last}"/><sheetViews><sheetView workbookViewId="0"><pane ySplit="7" topLeftCell="A8" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews><sheetFormatPr defaultRowHeight="22"/><cols>${cols}</cols><sheetData>${rows.join('')}</sheetData><autoFilter ref="A7:${endColumn}${last}"/><mergeCells count="2"><mergeCell ref="A1:${endColumn}1"/><mergeCell ref="A5:${endColumn}5"/></mergeCells><pageMargins left="0.3" right="0.3" top="0.5" bottom="0.5" header="0.2" footer="0.2"/><pageSetup orientation="landscape" paperSize="9" fitToWidth="1" fitToHeight="0"/></worksheet>`;
    return packageWorkbook(sheet,workbookStyles,config.sheetName||'Reporte');
  }

  return {build,buildGrid,packageFiles:zip};
})();
