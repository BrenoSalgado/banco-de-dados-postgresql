-- =============================================================================
-- 06_views_funcoes_triggers.sql — Visões, funções PL/pgSQL e regras de negócio em triggers
-- =============================================================================

SET search_path TO academico;

-- -----------------------------------------------------------------------------
-- VIEWS
-- -----------------------------------------------------------------------------

-- Histórico escolar: esconde as junções de quem só quer consultar.
CREATE OR REPLACE VIEW vw_historico AS
SELECT a.matricula,
       p.nome            AS aluno,
       c.codigo          AS curso,
       t.ano,
       t.semestre,
       di.codigo         AS cod_disciplina,
       di.nome           AS disciplina,
       di.carga_horaria,
       m.nota,
       m.frequencia,
       m.situacao
FROM matricula m
JOIN aluno a       ON a.pessoa_id = m.aluno_id
JOIN pessoa p      ON p.id = a.pessoa_id
JOIN curso c       ON c.id = a.curso_id
JOIN turma t       ON t.id = m.turma_id
JOIN disciplina di ON di.id = t.disciplina_id;

-- Ocupação das turmas (vagas restantes).
CREATE OR REPLACE VIEW vw_ocupacao_turmas AS
SELECT t.id                         AS turma_id,
       di.nome                      AS disciplina,
       t.ano || '/' || t.semestre   AS periodo,
       p.nome                       AS professor,
       t.vagas,
       count(m.aluno_id)            AS matriculados,
       t.vagas - count(m.aluno_id)  AS vagas_restantes
FROM turma t
JOIN disciplina di    ON di.id = t.disciplina_id
JOIN pessoa p         ON p.id = t.professor_id
LEFT JOIN matricula m ON m.turma_id = t.id
GROUP BY t.id, di.nome, p.nome;

-- -----------------------------------------------------------------------------
-- FUNÇÕES
-- -----------------------------------------------------------------------------

-- Coeficiente de rendimento (CR): média das notas ponderada pela carga horária,
-- considerando apenas disciplinas já encerradas. NULL se o aluno não tiver notas.
CREATE OR REPLACE FUNCTION coeficiente_rendimento(p_aluno integer)
RETURNS numeric
LANGUAGE sql
STABLE
AS $$
    SELECT round(sum(m.nota * di.carga_horaria) / sum(di.carga_horaria), 2)
    FROM academico.matricula m
    JOIN academico.turma t       ON t.id = m.turma_id
    JOIN academico.disciplina di ON di.id = t.disciplina_id
    WHERE m.aluno_id = p_aluno
      AND m.nota IS NOT NULL
$$;

-- Função que retorna tabela: disciplinas que o aluno já pode cursar
-- (não foi aprovado nem está cursando, e foi aprovado em todos os pré-requisitos).
CREATE OR REPLACE FUNCTION disciplinas_disponiveis(p_aluno integer)
RETURNS TABLE (codigo varchar, nome varchar)
LANGUAGE sql
STABLE
AS $$
    SELECT d.codigo, d.nome
    FROM academico.disciplina d
    WHERE NOT EXISTS (                                   -- não foi aprovado nem está cursando
        SELECT 1 FROM academico.matricula m
        JOIN academico.turma t ON t.id = m.turma_id
        WHERE m.aluno_id = p_aluno AND t.disciplina_id = d.id
          AND m.situacao IN ('APROVADO', 'CURSANDO')
    )
    AND NOT EXISTS (                                     -- e não falta nenhum pré-requisito
        SELECT 1 FROM academico.pre_requisito pr
        WHERE pr.disciplina_id = d.id
          AND NOT EXISTS (
              SELECT 1 FROM academico.matricula m
              JOIN academico.turma t ON t.id = m.turma_id
              WHERE m.aluno_id = p_aluno
                AND t.disciplina_id = pr.requisito_id
                AND m.situacao = 'APROVADO'
          )
    )
    ORDER BY d.codigo
$$;

-- -----------------------------------------------------------------------------
-- TRIGGERS
-- -----------------------------------------------------------------------------

-- 1) Não permite matrícula em turma lotada.
--    FOR UPDATE trava a linha da turma: duas matrículas simultâneas na última vaga
--    não conseguem passar as duas pela verificação.
CREATE OR REPLACE FUNCTION fn_verificar_vagas()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_vagas        integer;
    v_matriculados integer;
BEGIN
    SELECT vagas INTO v_vagas FROM academico.turma WHERE id = NEW.turma_id FOR UPDATE;
    SELECT count(*) INTO v_matriculados FROM academico.matricula WHERE turma_id = NEW.turma_id;

    IF v_matriculados >= v_vagas THEN
        RAISE EXCEPTION 'Turma % está lotada (% de % vagas ocupadas)',
            NEW.turma_id, v_matriculados, v_vagas
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_verificar_vagas
BEFORE INSERT ON matricula
FOR EACH ROW EXECUTE FUNCTION fn_verificar_vagas();

-- 2) Só matricula se o aluno foi aprovado em todos os pré-requisitos da disciplina.
CREATE OR REPLACE FUNCTION fn_verificar_pre_requisitos()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    v_faltando text;
BEGIN
    SELECT string_agg(req.codigo, ', ' ORDER BY req.codigo)
    INTO v_faltando
    FROM academico.turma t
    JOIN academico.pre_requisito pr ON pr.disciplina_id = t.disciplina_id
    JOIN academico.disciplina req   ON req.id = pr.requisito_id
    WHERE t.id = NEW.turma_id
      AND NOT EXISTS (
          SELECT 1
          FROM academico.matricula m
          JOIN academico.turma t2 ON t2.id = m.turma_id
          WHERE m.aluno_id = NEW.aluno_id
            AND t2.disciplina_id = pr.requisito_id
            AND m.situacao = 'APROVADO'
      );

    IF v_faltando IS NOT NULL THEN
        RAISE EXCEPTION 'Aluno % não cumpriu os pré-requisitos: %', NEW.aluno_id, v_faltando
            USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_verificar_pre_requisitos
BEFORE INSERT ON matricula
FOR EACH ROW EXECUTE FUNCTION fn_verificar_pre_requisitos();

-- 3) Especialização disjunta: uma pessoa não pode ser professor e aluno ao mesmo tempo.
CREATE OR REPLACE FUNCTION fn_especializacao_disjunta()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    IF TG_TABLE_NAME = 'professor'
       AND EXISTS (SELECT 1 FROM academico.aluno WHERE pessoa_id = NEW.pessoa_id) THEN
        RAISE EXCEPTION 'Pessoa % já é aluno', NEW.pessoa_id USING ERRCODE = 'check_violation';
    ELSIF TG_TABLE_NAME = 'aluno'
       AND EXISTS (SELECT 1 FROM academico.professor WHERE pessoa_id = NEW.pessoa_id) THEN
        RAISE EXCEPTION 'Pessoa % já é professor', NEW.pessoa_id USING ERRCODE = 'check_violation';
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_professor_disjunto
BEFORE INSERT OR UPDATE OF pessoa_id ON professor
FOR EACH ROW EXECUTE FUNCTION fn_especializacao_disjunta();

CREATE TRIGGER trg_aluno_disjunto
BEFORE INSERT OR UPDATE OF pessoa_id ON aluno
FOR EACH ROW EXECUTE FUNCTION fn_especializacao_disjunta();

-- 4) Auditoria: toda alteração de nota fica registrada (quem, quando, de quanto para quanto).
CREATE OR REPLACE FUNCTION fn_auditar_nota()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    INSERT INTO academico.auditoria_nota (aluno_id, turma_id, nota_antiga, nota_nova)
    VALUES (NEW.aluno_id, NEW.turma_id, OLD.nota, NEW.nota);
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auditar_nota
AFTER UPDATE OF nota ON matricula
FOR EACH ROW
WHEN (OLD.nota IS DISTINCT FROM NEW.nota)
EXECUTE FUNCTION fn_auditar_nota();

-- -----------------------------------------------------------------------------
-- Exemplos de uso
-- -----------------------------------------------------------------------------

-- Ranking de CR dos alunos
SELECT a.matricula, p.nome, coeficiente_rendimento(a.pessoa_id) AS cr
FROM aluno a
JOIN pessoa p ON p.id = a.pessoa_id
ORDER BY cr DESC NULLS LAST, p.nome;

-- O que o aluno 9 já pode cursar?
SELECT * FROM disciplinas_disponiveis(9);

-- Situação das turmas do semestre atual
SELECT * FROM vw_ocupacao_turmas WHERE periodo = '2026/1' ORDER BY turma_id;
