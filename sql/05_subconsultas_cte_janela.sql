-- =============================================================================
-- 05_subconsultas_cte_janela.sql — Subconsultas (aninhamento), CTEs e funções de janela
-- =============================================================================

SET search_path TO academico;

-- 1. Subconsulta escalar: professores que ganham acima da média geral.
SELECT p.nome, pr.salario,
       (SELECT round(avg(salario), 2) FROM professor) AS media_geral
FROM professor pr
JOIN pessoa p ON p.id = pr.pessoa_id
WHERE pr.salario > (SELECT avg(salario) FROM professor)
ORDER BY pr.salario DESC;

-- 2. Subconsulta correlacionada: professores que ganham acima da média do PRÓPRIO departamento.
SELECT p.nome, d.sigla, pr.salario
FROM professor pr
JOIN pessoa p       ON p.id = pr.pessoa_id
JOIN departamento d ON d.id = pr.departamento_id
WHERE pr.salario > (
    SELECT avg(pr2.salario)
    FROM professor pr2
    WHERE pr2.departamento_id = pr.departamento_id
)
ORDER BY d.sigla, pr.salario DESC;

-- 3. IN com subconsulta: professores que já deram aula para alunos de Estatística.
SELECT p.nome
FROM pessoa p
WHERE p.id IN (
    SELECT t.professor_id
    FROM turma t
    JOIN matricula m ON m.turma_id = t.id
    JOIN aluno a     ON a.pessoa_id = m.aluno_id
    JOIN curso c     ON c.id = a.curso_id
    WHERE c.codigo = 'EST'
)
ORDER BY p.nome;

-- 4. NOT EXISTS: professores que não lecionam nenhuma turma.
SELECT p.nome
FROM professor pr
JOIN pessoa p ON p.id = pr.pessoa_id
WHERE NOT EXISTS (SELECT 1 FROM turma t WHERE t.professor_id = pr.pessoa_id);

-- 5. Subconsulta no FROM (tabela derivada): curso com a maior média de notas.
SELECT curso, media
FROM (
    SELECT c.nome AS curso, round(avg(m.nota), 2) AS media
    FROM matricula m
    JOIN aluno a ON a.pessoa_id = m.aluno_id
    JOIN curso c ON c.id = a.curso_id
    WHERE m.nota IS NOT NULL
    GROUP BY c.nome
) AS medias
ORDER BY media DESC
LIMIT 1;

-- 6. CTE recursiva: TODOS os pré-requisitos (diretos e indiretos) de Inteligência Artificial,
--    com o nível de distância na cadeia.
WITH RECURSIVE cadeia (disciplina_id, nivel) AS (
    SELECT pr.requisito_id, 1
    FROM pre_requisito pr
    JOIN disciplina d ON d.id = pr.disciplina_id
    WHERE d.codigo = 'COMP401'
  UNION
    SELECT pr.requisito_id, c.nivel + 1
    FROM cadeia c
    JOIN pre_requisito pr ON pr.disciplina_id = c.disciplina_id
)
SELECT d.codigo, d.nome, min(c.nivel) AS nivel
FROM cadeia c
JOIN disciplina d ON d.id = c.disciplina_id
GROUP BY d.codigo, d.nome
ORDER BY nivel, d.codigo;

-- 7. Função de janela RANK: classificação dos alunos dentro de cada turma encerrada.
SELECT di.nome AS disciplina,
       p.nome  AS aluno,
       m.nota,
       rank() OVER (PARTITION BY m.turma_id ORDER BY m.nota DESC) AS posicao
FROM matricula m
JOIN turma t       ON t.id = m.turma_id
JOIN disciplina di ON di.id = t.disciplina_id
JOIN pessoa p      ON p.id = m.aluno_id
WHERE m.nota IS NOT NULL
ORDER BY di.nome, posicao, p.nome;

-- 8. Top 3 de cada turma (janela + filtro em CTE, já que WHERE não enxerga a janela).
WITH ranking AS (
    SELECT m.turma_id, m.aluno_id, m.nota,
           dense_rank() OVER (PARTITION BY m.turma_id ORDER BY m.nota DESC) AS pos
    FROM matricula m
    WHERE m.nota IS NOT NULL
)
SELECT di.nome AS disciplina, p.nome AS aluno, r.nota, r.pos
FROM ranking r
JOIN turma t       ON t.id = r.turma_id
JOIN disciplina di ON di.id = t.disciplina_id
JOIN pessoa p      ON p.id = r.aluno_id
WHERE r.pos <= 3
ORDER BY di.nome, r.pos, p.nome;

-- 9. Comparação com a média da turma sem GROUP BY (agregado como janela).
SELECT p.nome AS aluno,
       di.nome AS disciplina,
       m.nota,
       round(avg(m.nota) OVER (PARTITION BY m.turma_id), 2)          AS media_turma,
       round(m.nota - avg(m.nota) OVER (PARTITION BY m.turma_id), 2) AS diferenca
FROM matricula m
JOIN turma t       ON t.id = m.turma_id
JOIN disciplina di ON di.id = t.disciplina_id
JOIN pessoa p      ON p.id = m.aluno_id
WHERE m.nota IS NOT NULL AND di.codigo = 'COMP101'
ORDER BY diferenca DESC;

-- 10. Evolução de cada aluno entre semestres (LAG: valor da linha anterior na partição).
WITH media_semestre AS (
    SELECT m.aluno_id, t.ano, t.semestre, round(avg(m.nota), 2) AS media
    FROM matricula m
    JOIN turma t ON t.id = m.turma_id
    WHERE m.nota IS NOT NULL
    GROUP BY m.aluno_id, t.ano, t.semestre
)
SELECT p.nome,
       ms.ano || '/' || ms.semestre AS periodo,
       ms.media,
       ms.media - lag(ms.media) OVER (PARTITION BY ms.aluno_id ORDER BY ms.ano, ms.semestre) AS variacao
FROM media_semestre ms
JOIN pessoa p ON p.id = ms.aluno_id
ORDER BY p.nome, ms.ano, ms.semestre;
