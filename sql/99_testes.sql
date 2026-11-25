-- =============================================================================
-- 99_testes.sql — Testes automatizados das regras do banco
--
-- Cada bloco usa ASSERT (falha = erro = CI vermelho). Tudo roda dentro de uma
-- transação que termina em ROLLBACK, então os dados de exemplo não mudam.
-- =============================================================================

SET search_path TO academico;
SET client_min_messages TO warning;

BEGIN;

-- Restrições declarativas (CHECK, UNIQUE, FK) recusam dados inválidos
DO $$
BEGIN
    BEGIN
        INSERT INTO academico.matricula (aluno_id, turma_id, nota, frequencia) VALUES (9, 11, 11, 80);
        RAISE EXCEPTION 'nota 11 deveria violar o CHECK';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO academico.pessoa (nome, email, data_nascimento) VALUES ('X', 'email-invalido', '2000-01-01');
        RAISE EXCEPTION 'e-mail inválido deveria violar o CHECK';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO academico.pessoa (nome, email, data_nascimento)
        VALUES ('Outra Ana', 'ana.ribeiro@universidade.edu.br', '2000-01-01');
        RAISE EXCEPTION 'e-mail repetido deveria violar o UNIQUE';
    EXCEPTION WHEN unique_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO academico.turma (disciplina_id, professor_id, ano, semestre, vagas) VALUES (999, 1, 2026, 1, 10);
        RAISE EXCEPTION 'disciplina inexistente deveria violar a FK';
    EXCEPTION WHEN foreign_key_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO academico.pre_requisito VALUES (1, 1);
        RAISE EXCEPTION 'disciplina não pode ser pré-requisito de si mesma';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
END $$;

-- Coluna gerada: situação acompanha nota e frequência
DO $$
DECLARE v text;
BEGIN
    SELECT situacao INTO v FROM academico.matricula WHERE nota IS NULL LIMIT 1;
    ASSERT v = 'CURSANDO', 'sem nota deveria ser CURSANDO';

    ASSERT NOT EXISTS (SELECT 1 FROM academico.matricula
                       WHERE situacao = 'APROVADO' AND (nota < 6 OR frequencia < 75)),
           'aprovado com nota < 6 ou frequência < 75%';
    ASSERT NOT EXISTS (SELECT 1 FROM academico.matricula
                       WHERE situacao = 'REPROVADO' AND nota >= 6 AND frequencia >= 75),
           'reprovado com nota e frequência suficientes';
END $$;

-- Trigger: turma lotada recusa matrícula
DO $$
DECLARE
    v_turma integer;
    v_aluno integer;
BEGIN
    SELECT turma_id INTO v_turma FROM academico.vw_ocupacao_turmas WHERE vagas_restantes = 0 LIMIT 1;
    ASSERT v_turma IS NOT NULL, 'os dados de exemplo deveriam ter uma turma lotada';

    -- escolhe um aluno que cumpre os pré-requisitos, para isolar a regra de vagas
    SELECT a.pessoa_id INTO v_aluno
    FROM academico.aluno a
    WHERE a.pessoa_id NOT IN (SELECT aluno_id FROM academico.matricula WHERE turma_id = v_turma)
      AND EXISTS (SELECT 1 FROM academico.disciplinas_disponiveis(a.pessoa_id) dd
                  JOIN academico.disciplina d ON d.codigo = dd.codigo
                  JOIN academico.turma t ON t.disciplina_id = d.id
                  WHERE t.id = v_turma)
    LIMIT 1;
    ASSERT v_aluno IS NOT NULL, 'deveria existir aluno apto fora da turma lotada';

    BEGIN
        INSERT INTO academico.matricula (aluno_id, turma_id) VALUES (v_aluno, v_turma);
        RAISE EXCEPTION 'matrícula em turma lotada deveria falhar';
    EXCEPTION WHEN check_violation THEN
        ASSERT SQLERRM LIKE '%lotada%', SQLERRM;
    END;

    -- abrindo uma vaga, a mesma matrícula passa
    UPDATE academico.turma SET vagas = vagas + 1 WHERE id = v_turma;
    INSERT INTO academico.matricula (aluno_id, turma_id) VALUES (v_aluno, v_turma);
END $$;

-- Trigger: pré-requisitos
DO $$
DECLARE v_turma_ia integer;
BEGIN
    SELECT t.id INTO v_turma_ia FROM academico.turma t
    JOIN academico.disciplina d ON d.id = t.disciplina_id WHERE d.codigo = 'COMP401';

    -- ninguém foi aprovado em Estruturas de Dados ainda, então ninguém pode cursar IA
    BEGIN
        INSERT INTO academico.matricula (aluno_id, turma_id) VALUES (9, v_turma_ia);
        RAISE EXCEPTION 'matrícula sem pré-requisito deveria falhar';
    EXCEPTION WHEN check_violation THEN
        ASSERT SQLERRM LIKE '%COMP201%', 'mensagem deveria citar Estruturas de Dados: ' || SQLERRM;
    END;
END $$;

-- Trigger: especialização disjunta
DO $$
BEGIN
    BEGIN
        INSERT INTO academico.aluno (pessoa_id, matricula, curso_id, ano_ingresso) VALUES (1, '260199999', 1, 2026);
        RAISE EXCEPTION 'professor não pode virar aluno';
    EXCEPTION WHEN check_violation THEN NULL;
    END;

    BEGIN
        INSERT INTO academico.professor (pessoa_id, siape, departamento_id, titulacao, salario, data_admissao)
        VALUES (9, '9999999', 1, 'Mestre', 9000, current_date);
        RAISE EXCEPTION 'aluno não pode virar professor';
    EXCEPTION WHEN check_violation THEN NULL;
    END;
END $$;

-- Trigger: auditoria de notas
DO $$
DECLARE
    v_antes integer := (SELECT count(*) FROM academico.auditoria_nota);
    r record;
BEGIN
    SELECT aluno_id, turma_id INTO r FROM academico.matricula WHERE nota IS NULL ORDER BY 1, 2 LIMIT 1;

    UPDATE academico.matricula SET nota = 8.0, frequencia = 90 WHERE aluno_id = r.aluno_id AND turma_id = r.turma_id;
    UPDATE academico.matricula SET nota = 8.0                  WHERE aluno_id = r.aluno_id AND turma_id = r.turma_id; -- não muda
    UPDATE academico.matricula SET nota = 8.5                  WHERE aluno_id = r.aluno_id AND turma_id = r.turma_id;

    ASSERT (SELECT count(*) FROM academico.auditoria_nota) = v_antes + 2,
           'deveria registrar só as 2 alterações reais de nota';
    ASSERT EXISTS (SELECT 1 FROM academico.auditoria_nota
                   WHERE aluno_id = r.aluno_id AND nota_antiga = 8.0 AND nota_nova = 8.5);
    ASSERT (SELECT situacao FROM academico.matricula
            WHERE aluno_id = r.aluno_id AND turma_id = r.turma_id) = 'APROVADO';
END $$;

-- Funções
DO $$
DECLARE
    v_cr numeric;
    v_esperado numeric;
BEGIN
    -- CR calculado pela função = média ponderada calculada "na mão"
    SELECT round(sum(nota * carga_horaria) / sum(carga_horaria), 2) INTO v_esperado
    FROM academico.vw_historico WHERE matricula = (SELECT matricula FROM academico.aluno WHERE pessoa_id = 9)
      AND nota IS NOT NULL;
    v_cr := academico.coeficiente_rendimento(9);
    ASSERT v_cr = v_esperado, format('CR %s <> esperado %s', v_cr, v_esperado);
    ASSERT v_cr BETWEEN 0 AND 10;

    -- professor não tem notas: CR nulo
    ASSERT academico.coeficiente_rendimento(1) IS NULL;

    -- quem nunca cursou nada só pode fazer disciplinas sem pré-requisito
    INSERT INTO academico.pessoa (id, nome, email, data_nascimento) VALUES (500, 'Calouro Teste', 'calouro@universidade.edu.br', '2008-01-01');
    INSERT INTO academico.aluno (pessoa_id, matricula, curso_id, ano_ingresso) VALUES (500, '260100500', 1, 2026);
    ASSERT (SELECT count(*) FROM academico.disciplinas_disponiveis(500))
         = (SELECT count(*) FROM academico.disciplina d
            WHERE NOT EXISTS (SELECT 1 FROM academico.pre_requisito pr WHERE pr.disciplina_id = d.id)),
           'calouro deveria ver exatamente as disciplinas sem pré-requisito';
END $$;

-- Consultas de estudo: resultados conhecidos
DO $$
DECLARE v integer;
BEGIN
    -- CTE recursiva: IA tem 6 pré-requisitos diretos e indiretos
    WITH RECURSIVE cadeia (id) AS (
        SELECT requisito_id FROM academico.pre_requisito
        WHERE disciplina_id = (SELECT id FROM academico.disciplina WHERE codigo = 'COMP401')
      UNION
        SELECT pr.requisito_id FROM cadeia c JOIN academico.pre_requisito pr ON pr.disciplina_id = c.id
    )
    SELECT count(*) INTO v FROM cadeia;
    ASSERT v = 6, format('IA deveria ter 6 pré-requisitos, tem %s', v);

    -- Física não oferece curso (aparece só com LEFT JOIN)
    ASSERT NOT EXISTS (SELECT 1 FROM academico.curso c JOIN academico.departamento d ON d.id = c.departamento_id
                       WHERE d.sigla = 'DFIS');

    -- Professor Eduardo (DFIS) não leciona nenhuma turma
    ASSERT NOT EXISTS (SELECT 1 FROM academico.turma t JOIN academico.pessoa p ON p.id = t.professor_id
                       WHERE p.nome = 'Eduardo Nunes');
END $$;

ROLLBACK;

\echo 'Todos os testes passaram.'
