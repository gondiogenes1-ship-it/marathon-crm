begin;
-- Estos dos RPC de lectura ya verifican usuario activo y admiten consultar
-- cualquier ficha para ese equipo. Encapsulan ahora las funciones privadas
-- del ledger, igual que los otros RPC de cuenta, sin abrir las tablas.
alter function public.marathon_patient_history(text,text,jsonb,integer)security definer;
alter function public.marathon_bonus_get(text,jsonb,integer)security definer;
revoke all on function public.marathon_patient_history(text,text,jsonb,integer),public.marathon_bonus_get(text,jsonb,integer)from public,anon;
grant execute on function public.marathon_patient_history(text,text,jsonb,integer),public.marathon_bonus_get(text,jsonb,integer)to authenticated;
commit;
