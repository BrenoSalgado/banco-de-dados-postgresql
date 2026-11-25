-- =============================================================================
-- 04_juncoes_e_agregacoes.sql — Junções, agregação, operações de conjunto e divisão
-- =============================================================================

SET search_path TO academico;

-- 1. Cada curso com seu departamento e o nome do coordenador (INNER JOIN).
--    curso ⋈ departamento ⋈ (professor ⋈ pessoa)
SELECT c.codigo,
       c.nome      AS curso,
       d.sigla     AS departamento,
       p.nome      AS coordenador
FROM curso c
JOIN departamento d ON d.id = c.departamento_id
JOIN pessoa p       ON p.id = c.coordenador_id
ORDER BY c.codigo;

-- 2. Departamentos e quantos cursos cada um oferece, incluindo os que não oferecem nenhum (LEFT JOIN).
SELECT d.sigla,
       count(c.id) AS qtd_cursos
FROM departamento d
LEFT JOIN curso c ON c.departamento_id = d.id
GROUP BY d.sigla
ORDER BY qtd_cursos DESC, d.sigla;

-- 3. Turmas sem nenhum aluno matriculado (anti-junção com LEFT JOIN ... IS NULL).
SELECT t.id, di.nome AS disciplina, t.ano, t.semestre
FROM turma t
JOIN disciplina di    ON di.id = t.disciplina_id
LEFT JOIN matricula m ON m.turma_id = t.id
WHERE m.turma_id IS NULL;

-- 4. Pré-requisitos de cada disciplina (auto-junção: disciplina aparece duas vezes).
SELECT d.codigo AS disciplina,
       d.nome,
       r.codigo AS requisito,
       r.nome   AS nome_requisito
FROM pre_requisito pr
JOIN disciplina d ON d.id = pr.disciplina_id
JOIN disciplina r ON r.id = pr.requisito_id
ORDER BY d.codigo, r.codigo;

-- 5. Média, mínimo, máximo e taxa de aprovação por turma já encerrada (GROUP BY + agregados + FILTER).
--    γ turma; avg(nota), min(nota), max(nota), count(*) (matricula)
SELECT t.ano || '/' || t.semestre               AS periodo,
       di.nome                                  AS disciplina,
       count(*)                                 AS alunos,
       round(avg(m.nota), 2)                    AS media,
       min(m.nota)                              AS menor,
       max(m.nota)                              AS maior,
       round(100.0 * count(*) FILTER (WHERE m.situacao = 'APROVADO') / count(*), 1) AS pct_aprovacao
FROM matricula m
JOIN turma t       ON t.id = m.turma_id
JOIN disciplina di ON di.id = t.disciplina_id
WHERE m.nota IS NOT NULL
GROUP BY t.id, t.ano, t.semestre, di.nome
ORDER BY t.ano, t.semestre, di.nome;

-- 6. Disciplinas com média de notas abaixo de 7 (HAVING filtra grupos; WHERE filtra linhas).
SELECT di.nome, round(avg(m.nota), 2) AS media
FROM matricula m
JOIN turma t       ON t.id = m.turma_id
JOIN disciplina di ON di.id = t.disciplina_id
WHERE m.nota IS NOT NULL
GROUP BY di.nome
HAVING avg(m.nota) < 7
ORDER BY media;

-- 7. Folha salarial por departamento e por titulação, com subtotais (ROLLUP).
SELECT coalesce(d.sigla, 'TOTAL')        AS departamento,
       coalesce(pr.titulacao, '(todas)') AS titulacao,
       count(*)                          AS professores,
       sum(pr.salario)                   AS folha
FROM professor pr
JOIN departamento d ON d.id = pr.departamento_id
GROUP BY ROLLUP (d.sigla, pr.titulacao)
ORDER BY d.sigla NULLS LAST, pr.titulacao NULLS LAST;

-- 8. UNION: todas as pessoas com o papel que exercem.
SELECT p.nome, 'Professor' AS papel FROM pessoa p JOIN professor pr ON pr.pessoa_id = p.id
UNION
SELECT p.nome, 'Aluno'            FROM pessoa p JOIN aluno a     ON a.pessoa_id = p.id
ORDER BY papel DESC, nome;

-- 9. INTERSECT: alunos aprovados tanto em Cálculo I quanto em Matemática Discreta.
--    π aluno (σ disc = Cálculo I ∧ aprovado) ∩ π aluno (σ disc = Discreta ∧ aprovado)
SELECT m.aluno_id FROM matricula m JOIN turma t ON t.id = m.turma_id
WHERE t.disciplina_id = (SELECT id FROM disciplina WHERE codigo = 'MAT101') AND m.situacao = 'APROVADO'
INTERSECT
SELECT m.aluno_id FROM matricula m JOIN turma t ON t.id = m.turma_id
WHERE t.disciplina_id = (SELECT id FROM disciplina WHERE codigo = 'MAT103') AND m.situacao = 'APROVADO'
ORDER BY aluno_id;

-- 10. EXCEPT: alunos de Computação (BCC) que ainda não foram aprovados em Algoritmos I.
SELECT a.pessoa_id FROM aluno a JOIN curso c ON c.id = a.curso_id WHERE c.codigo = 'BCC'
EXCEPT
SELECT m.aluno_id FROM matricula m JOIN turma t ON t.id = m.turma_id
WHERE t.disciplina_id = (SELECT id FROM disciplina WHERE codigo = 'COMP101') AND m.situacao = 'APROVADO'
ORDER BY 1;

-- 11. DIVISÃO relacional: alunos aprovados em TODAS as disciplinas do 1º semestre do BCC
--     (Algoritmos I, Cálculo I e Matemática Discreta).
--     aprovados(aluno, disciplina) ÷ π disciplina (primeiro_semestre)
--     Em SQL: "não existe disciplina do conjunto em que o aluno não tenha sido aprovado".
WITH primeiro_semestre AS (
    SELECT id FROM disciplina WHERE codigo IN ('COMP101', 'MAT101', 'MAT103')
)
SELECT p.nome
FROM aluno a
JOIN pessoa p ON p.id = a.pessoa_id
WHERE NOT EXISTS (
    SELECT 1
    FROM primeiro_semestre ps
    WHERE NOT EXISTS (
        SELECT 1
        FROM matricula m
        JOIN turma t ON t.id = m.turma_id
        WHERE m.aluno_id = a.pessoa_id
          AND t.disciplina_id = ps.id
          AND m.situacao = 'APROVADO'
    )
)
ORDER BY p.nome;
