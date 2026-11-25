# 3. Álgebra relacional ↔ SQL

Cada operador da álgebra relacional com o equivalente em SQL sobre o esquema deste repositório.

| Operador | Símbolo | SQL |
|---|---|---|
| Seleção | σ | `WHERE` |
| Projeção | π | lista do `SELECT` (+ `DISTINCT`, pois a álgebra trabalha com conjuntos) |
| Renomeação | ρ | `AS` |
| Produto cartesiano | × | `CROSS JOIN` / `FROM a, b` |
| Junção | ⋈ | `JOIN ... ON` |
| Junção externa | ⟕ ⟖ ⟗ | `LEFT` / `RIGHT` / `FULL JOIN` |
| União | ∪ | `UNION` |
| Interseção | ∩ | `INTERSECT` |
| Diferença | − | `EXCEPT` |
| Divisão | ÷ | `NOT EXISTS` duplo |
| Agregação | γ | `GROUP BY` + funções de agregação |

## Exemplos

**Seleção e projeção** — nome das disciplinas de 90 horas:

```
π nome ( σ carga_horaria = 90 (disciplina) )
```
```sql
SELECT DISTINCT nome FROM disciplina WHERE carga_horaria = 90;
```

**Renomeação e auto-junção** — pares (disciplina, pré-requisito):

```
D ← ρ D(disciplina)        R ← ρ R(disciplina)
π D.nome, R.nome ( (pre_requisito ⋈ disciplina_id = D.id D) ⋈ requisito_id = R.id R )
```
```sql
SELECT d.nome, r.nome
FROM pre_requisito pr
JOIN disciplina d ON d.id = pr.disciplina_id
JOIN disciplina r ON r.id = pr.requisito_id;
```

**Produto cartesiano + seleção = junção** — as duas formas são equivalentes:

```
σ curso.departamento_id = departamento.id (curso × departamento)  ≡  curso ⋈ departamento
```
```sql
SELECT * FROM curso, departamento WHERE curso.departamento_id = departamento.id;
SELECT * FROM curso JOIN departamento ON curso.departamento_id = departamento.id;
```

**Junção externa** — departamentos com ou sem curso:

```
departamento ⟕ id = departamento_id curso
```
```sql
SELECT d.sigla, c.nome FROM departamento d LEFT JOIN curso c ON c.departamento_id = d.id;
```

**União, interseção e diferença** — exigem relações compatíveis (mesmo número e tipo de atributos):

```
AprovCalc ← π aluno_id ( σ disciplina = 'MAT101' ∧ situacao = 'APROVADO' (matricula ⋈ turma) )
AprovDisc ← π aluno_id ( σ disciplina = 'MAT103' ∧ situacao = 'APROVADO' (matricula ⋈ turma) )

AprovCalc ∩ AprovDisc     -- aprovados nas duas
AprovCalc − AprovDisc     -- aprovados só em Cálculo
```

Ver consultas 8 a 10 de [`04_juncoes_e_agregacoes.sql`](../sql/04_juncoes_e_agregacoes.sql).

**Divisão** — alunos aprovados em *todas* as disciplinas de um conjunto:

```
Aprovados(aluno, disciplina) ← π aluno_id, disciplina_id ( σ situacao = 'APROVADO' (matricula ⋈ turma) )
Conjunto(disciplina)         ← π id ( σ codigo ∈ {COMP101, MAT101, MAT103} (disciplina) )

Aprovados ÷ Conjunto
```

SQL não tem operador de divisão. A tradução clássica usa dupla negação:
*"não existe disciplina do conjunto em que o aluno não tenha sido aprovado"*.

```sql
SELECT a.pessoa_id
FROM aluno a
WHERE NOT EXISTS (
    SELECT 1 FROM conjunto c
    WHERE NOT EXISTS (
        SELECT 1 FROM aprovados ap
        WHERE ap.aluno_id = a.pessoa_id AND ap.disciplina_id = c.id
    )
);
```

Ver consulta 11 de [`04_juncoes_e_agregacoes.sql`](../sql/04_juncoes_e_agregacoes.sql).

**Agregação** — média de notas por turma:

```
turma_id γ avg(nota) → media, count(*) → alunos (matricula)
```
```sql
SELECT turma_id, avg(nota) AS media, count(*) AS alunos
FROM matricula
GROUP BY turma_id;
```
