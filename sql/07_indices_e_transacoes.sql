-- =============================================================================
-- 07_indices_e_transacoes.sql — Índices, plano de execução e controle de transações
-- =============================================================================

SET search_path TO academico;
SET client_min_messages TO notice;

-- -----------------------------------------------------------------------------
-- ÍNDICES
-- PKs e UNIQUEs já criam índices automaticamente. Os abaixo atendem consultas
-- frequentes que essas chaves não cobrem.
-- -----------------------------------------------------------------------------

-- A PK de matricula é (aluno_id, turma_id): serve para "matrículas de um aluno",
-- mas não para "alunos de uma turma". Este índice cobre o segundo caso
-- (usado pelo trigger de vagas e por várias junções).
CREATE INDEX IF NOT EXISTS idx_matricula_turma ON matricula (turma_id);

-- FKs não ganham índice automático no PostgreSQL.
CREATE INDEX IF NOT EXISTS idx_turma_disciplina ON turma (disciplina_id);
CREATE INDEX IF NOT EXISTS idx_turma_professor  ON turma (professor_id);
CREATE INDEX IF NOT EXISTS idx_aluno_curso      ON aluno (curso_id);

-- Índice de expressão: busca por nome sem diferenciar maiúsculas/minúsculas.
CREATE INDEX IF NOT EXISTS idx_pessoa_nome_lower ON pessoa (lower(nome));

-- Índice parcial: só as matrículas em andamento (consulta comum e pequena fração da tabela).
CREATE INDEX IF NOT EXISTS idx_matricula_cursando ON matricula (turma_id) WHERE nota IS NULL;

ANALYZE;

-- Plano de execução de uma consulta que pode usar o índice de expressão.
-- (Com poucas linhas o planejador pode preferir Seq Scan — é o comportamento correto.)
EXPLAIN
SELECT id, nome FROM pessoa WHERE lower(nome) = 'ana ribeiro';

-- -----------------------------------------------------------------------------
-- TRANSAÇÕES
-- -----------------------------------------------------------------------------

-- Atomicidade: reajuste de 5% para todos os mestres + promoção de um deles.
-- Ou as duas alterações acontecem, ou nenhuma.
BEGIN;
    UPDATE professor SET salario = salario * 1.05 WHERE titulacao = 'Mestre';
    UPDATE professor SET titulacao = 'Doutor' WHERE siape = '1123402';
COMMIT;

-- SAVEPOINT: desfaz só parte da transação.
BEGIN;
    -- lança a nota de uma matrícula em andamento
    UPDATE matricula SET nota = 7.5, frequencia = 90
    WHERE (aluno_id, turma_id) = (SELECT aluno_id, turma_id FROM matricula
                                  WHERE nota IS NULL ORDER BY aluno_id, turma_id LIMIT 1);

    SAVEPOINT antes_de_apagar;
    DELETE FROM auditoria_nota;            -- engano!
    ROLLBACK TO SAVEPOINT antes_de_apagar; -- volta para antes do DELETE

    -- O lançamento de nota continua valendo e foi registrado na auditoria:
    SELECT aluno_id, turma_id, nota_antiga, nota_nova FROM auditoria_nota;
ROLLBACK; -- descarta tudo para manter os dados de exemplo intactos

-- Tratamento de erro: um aluno que cumpre os pré-requisitos tenta entrar numa turma
-- lotada; o trigger de vagas recusa e o bloco captura a exceção, sem abortar o script.
DO $$
DECLARE
    v_turma integer := (SELECT turma_id FROM vw_ocupacao_turmas WHERE vagas_restantes = 0 LIMIT 1);
    v_aluno integer := (
        SELECT a.pessoa_id
        FROM aluno a
        JOIN turma t ON t.id = v_turma
        JOIN disciplina d ON d.id = t.disciplina_id
        WHERE a.pessoa_id NOT IN (SELECT aluno_id FROM matricula WHERE turma_id = v_turma)
          AND d.codigo IN (SELECT codigo FROM disciplinas_disponiveis(a.pessoa_id))
        ORDER BY a.pessoa_id
        LIMIT 1);
BEGIN
    INSERT INTO academico.matricula (aluno_id, turma_id) VALUES (v_aluno, v_turma);
    RAISE NOTICE 'Não deveria chegar aqui';
EXCEPTION
    WHEN check_violation THEN
        RAISE NOTICE 'Matrícula recusada como esperado: %', SQLERRM;
END;
$$;

-- Níveis de isolamento (para estudo):
--   READ COMMITTED (padrão) — cada comando vê o que já foi confirmado antes dele.
--   REPEATABLE READ         — a transação inteira vê o mesmo "retrato" dos dados.
--   SERIALIZABLE            — resultado equivalente a executar as transações em fila;
--                             o banco aborta uma delas se detectar conflito.
BEGIN TRANSACTION ISOLATION LEVEL REPEATABLE READ;
    SELECT count(*) AS matriculas_vistas FROM matricula;
COMMIT;
