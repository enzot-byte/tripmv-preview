-- ================================================================
-- DIAGNOSTICO READ-ONLY do Supabase — TripMV
-- Cole no Supabase Dashboard > SQL Editor e clique RUN.
-- SO FAZ LEITURA (SELECT em catalogos + contagens). NAO altera nada.
-- Copie/print o resultado e mande de volta.
-- ================================================================
WITH checks AS (
  SELECT 1 AS ord, 'RLS_desabilitado_em' AS verificacao,
    COALESCE(NULLIF((SELECT string_agg(relname, ', ' ORDER BY relname) FROM pg_class
      WHERE relnamespace='public'::regnamespace AND relkind='r' AND NOT relrowsecurity),''),
      '(nenhuma - todas com RLS)') AS resultado
  UNION ALL SELECT 2, 'policies_USING(true)_ou_CHECK(true)',
    COALESCE(NULLIF((SELECT string_agg(tablename||'.'||policyname||' ['||cmd||']', ', ' ORDER BY tablename)
      FROM pg_policies WHERE schemaname='public' AND (qual='true' OR with_check='true')),''),'(nenhuma)')
  UNION ALL SELECT 3, 'bookings_no_realtime',
    CASE WHEN EXISTS (SELECT 1 FROM pg_publication_tables
      WHERE pubname='supabase_realtime' AND schemaname='public' AND tablename='bookings')
      THEN 'SIM (ja publicada)' ELSE 'NAO (precisa da migration)' END
  UNION ALL SELECT 4, 'tabelas_no_realtime',
    (SELECT string_agg(tablename, ', ' ORDER BY tablename) FROM pg_publication_tables
      WHERE pubname='supabase_realtime' AND schemaname='public')
  UNION ALL SELECT 5, 'app_users_policies_SELECT',
    COALESCE((SELECT string_agg(policyname||' roles='||array_to_string(roles,'/')||' using='||COALESCE(qual,'null'),' | ')
      FROM pg_policies WHERE schemaname='public' AND tablename='app_users' AND cmd='SELECT'),'(sem policy SELECT)')
  UNION ALL SELECT 6, 'user_sessions_policies_SELECT',
    COALESCE((SELECT string_agg(policyname||' roles='||array_to_string(roles,'/')||' using='||COALESCE(qual,'null'),' | ')
      FROM pg_policies WHERE schemaname='public' AND tablename='user_sessions' AND cmd='SELECT'),'(sem policy)')
  UNION ALL SELECT 7, 'get_session_tenant_id_def',
    COALESCE((SELECT
        (CASE WHEN prosecdef THEN 'SECURITY DEFINER' ELSE 'SECURITY INVOKER' END)
        || (CASE WHEN prosrc ILIKE '%app_users%' THEN ' + usa app_users, anon vira NULL' ELSE ' + le user_sessions direto' END)
      FROM pg_proc WHERE proname='get_session_tenant_id' LIMIT 1),
      '(funcao nao existe)')
  UNION ALL SELECT 8, 'bookings_tenant_id_NULL',
    (SELECT count(*)::text FROM bookings WHERE tenant_id IS NULL)
  UNION ALL SELECT 9, 'bookings_duplicados_ativos_mesmo_slot',
    (SELECT count(*)::text FROM (SELECT tenant_id,date,time_slot,machine_id FROM bookings
      WHERE status NOT IN ('NO_SHOW','NOT_FIT','TRANSFERRED') GROUP BY 1,2,3,4 HAVING count(*)>1) d)
  UNION ALL SELECT 10, 'bookings_indices_unique',
    (SELECT string_agg(indexname, ', ' ORDER BY indexname) FROM pg_indexes
      WHERE schemaname='public' AND tablename='bookings' AND indexdef ILIKE '%unique%')
  UNION ALL SELECT 11, 'total_tenants', (SELECT count(*)::text FROM tenants)
  UNION ALL SELECT 12, 'qtd_funcoes_SECURITY_DEFINER',
    (SELECT count(*)::text FROM pg_proc p JOIN pg_namespace n ON n.oid=p.pronamespace
      WHERE n.nspname='public' AND p.prosecdef)
)
SELECT verificacao, resultado FROM checks ORDER BY ord;
