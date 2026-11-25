-- =============================================================================
-- 03_consultas_basicas.sql — Seleção, projeção, filtros e ordenação
--
-- Cada consulta traz a pergunta em linguagem natural e, quando faz sentido,
-- a expressão equivalente em álgebra relacional.
-- =============================================================================

SET search_path TO academico;

-- 1. Nome e carga horária das disciplinas com 90 horas.
--    π nome, carga_horaria ( σ carga_horaria = 90 (disciplina) )
SELECT nome, carga_horaria
FROM disciplina
WHERE carga_horaria = 90
ORDER BY nome;

-- 2. Professores doutores com salário acima de R$ 14.000, do maior para o menor salário.
--    σ titulacao = 'Doutor' ∧ salario > 14000 (professor)
SELECT siape, titulacao, salario
FROM professor
WHERE titulacao = 'Doutor'
  AND salario > 14000
ORDER BY salario DESC;

-- 3. Pessoas cujo nome começa com "Ma" (LIKE / ILIKE).
SELECT nome, email
FROM pessoa
WHERE nome ILIKE 'ma%'
ORDER BY nome;

-- 4. Professores admitidos entre 2010 e 2015 (BETWEEN) — usando junção para trazer o nome.
SELECT p.nome, pr.data_admissao
FROM professor pr
JOIN pessoa p ON p.id = pr.pessoa_id
WHERE pr.data_admissao BETWEEN DATE '2010-01-01' AND DATE '2015-12-31'
ORDER BY pr.data_admissao;

-- 5. Matrículas ainda sem nota (IS NULL) — disciplinas em andamento.
SELECT aluno_id, turma_id, situacao
FROM matricula
WHERE nota IS NULL
ORDER BY turma_id, aluno_id;

-- 6. Quais anos de ingresso existem? (DISTINCT)
--    π ano_ingresso (aluno)   — a projeção da álgebra relacional já elimina repetidos
SELECT DISTINCT ano_ingresso
FROM aluno
ORDER BY ano_ingresso;

-- 7. As 5 maiores notas já lançadas (ORDER BY + LIMIT).
SELECT aluno_id, turma_id, nota
FROM matricula
WHERE nota IS NOT NULL
ORDER BY nota DESC, aluno_id
LIMIT 5;

-- 8. Disciplinas de Computação OU de Matemática (IN), com expressão calculada.
SELECT codigo,
       nome,
       carga_horaria,
       carga_horaria / 15 AS creditos
FROM disciplina
WHERE departamento_id IN (SELECT id FROM departamento WHERE sigla IN ('DCOMP', 'DMAT'))
ORDER BY codigo;

-- 9. Idade de cada aluno hoje (funções de data).
SELECT p.nome,
       date_part('year', age(current_date, p.data_nascimento))::int AS idade
FROM aluno a
JOIN pessoa p ON p.id = a.pessoa_id
ORDER BY idade DESC, p.nome;

-- 10. Faixa salarial de cada professor (CASE).
SELECT p.nome,
       pr.salario,
       CASE
           WHEN pr.salario >= 14000 THEN 'Faixa A'
           WHEN pr.salario >= 12000 THEN 'Faixa B'
           ELSE 'Faixa C'
       END AS faixa
FROM professor pr
JOIN pessoa p ON p.id = pr.pessoa_id
ORDER BY pr.salario DESC;
