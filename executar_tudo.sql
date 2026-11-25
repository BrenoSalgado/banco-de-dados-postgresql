-- Executa todos os scripts em ordem. Uso:
--   psql -U postgres -d postgres -v ON_ERROR_STOP=1 -f executar_tudo.sql

\set ON_ERROR_STOP on
\encoding UTF8

\echo '== 01 Esquema'
\ir sql/01_schema.sql
\echo '== 02 Dados de exemplo'
\ir sql/02_dados.sql
\echo '== 03 Consultas básicas'
\ir sql/03_consultas_basicas.sql
\echo '== 04 Junções e agregações'
\ir sql/04_juncoes_e_agregacoes.sql
\echo '== 05 Subconsultas, CTEs e janelas'
\ir sql/05_subconsultas_cte_janela.sql
\echo '== 06 Views, funções e triggers'
\ir sql/06_views_funcoes_triggers.sql
\echo '== 07 Índices e transações'
\ir sql/07_indices_e_transacoes.sql
\echo '== 99 Testes'
\ir sql/99_testes.sql
