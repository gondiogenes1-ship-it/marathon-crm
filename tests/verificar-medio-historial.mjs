import assert from 'node:assert/strict';
import {historyMediumDetail} from '../public/saldo.js';

assert.equal(historyMediumDetail({tipo:'INGRESO',medio:'EFECTIVO'}),'Efectivo');
assert.equal(historyMediumDetail({tipo:'INGRESO',medio:'TRANSFERENCIA'}),'Transferencia');
// Una devolución puede usar otro medio distinto del ingreso original.
assert.equal(historyMediumDetail({tipo:'DEVOLUCION',medio:'TRANSFERENCIA',medio_origen:'EFECTIVO'}),'Transferencia');
assert.equal(historyMediumDetail({tipo:'APLICACION',medio_origen:'TRANSFERENCIA'}),'Pago original: Transferencia · Sin entrada ni salida de dinero');
assert.equal(historyMediumDetail({tipo:'REVERSO_APLICACION',medio_origen:'EFECTIVO'}),'Pago original: Efectivo · Sin entrada ni salida de dinero');
assert.equal(historyMediumDetail({tipo:'INGRESO'}),'Medio no registrado');
assert.equal(historyMediumDetail({tipo:'APLICACION'}),'Sin entrada ni salida de dinero');
console.log('OK: medio real del cobro/devolución, medio original de aplicaciones y ausencia explícita sin asumir efectivo.');
