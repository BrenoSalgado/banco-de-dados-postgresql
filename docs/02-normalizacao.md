# 2. Normalização: da planilha às tabelas

Como as tabelas de matrícula chegariam ao esquema atual se partíssemos de uma
planilha única, aplicando 1FN, 2FN e 3FN.

## Ponto de partida: tabela não normalizada

| matricula | aluno | curso | coord_curso | turma | disciplina | carga_h | professor | titulacao_prof | nota | freq |
|---|---|---|---|---|---|---|---|---|---|---|
| 250100002 | Mariana Souza | BCC | Ana Ribeiro | 1, 2, 3 | Algoritmos I, Cálculo I, Discreta | 90, 90, 60 | Carlos, Juliana, Marcos | Mestre, Doutor, Mestre | 6.4, 9.9, 8.4 | 75, 75, 95 |

Problemas: células com vários valores, dados repetidos em cada linha e **anomalias**:

- **Inserção**: não dá para cadastrar uma disciplina sem ter um aluno matriculado nela.
- **Atualização**: se a Juliana virar titular, é preciso alterar todas as linhas em que ela aparece.
- **Remoção**: apagar o último aluno de uma turma apaga também quem era o professor dela.

## 1ª Forma Normal — só valores atômicos

Cada célula com um único valor: uma linha por (aluno, turma).

**MATRICULA_1FN** (<u>matricula</u>, <u>turma</u>, aluno, curso, coord_curso, disciplina, carga_h, professor, titulacao_prof, nota, freq)

## 2ª Forma Normal — sem dependências parciais da chave

Com a chave composta (matricula, turma), existem atributos que dependem de **só uma parte** dela:

- `matricula → aluno, curso, coord_curso`
- `turma → disciplina, carga_h, professor, titulacao_prof`
- `matricula, turma → nota, freq` (dependência total ✔)

Separando:

- **ALUNO** (<u>matricula</u>, aluno, curso, coord_curso)
- **TURMA** (<u>turma</u>, disciplina, carga_h, professor, titulacao_prof)
- **MATRICULA** (<u>matricula</u>, <u>turma</u>, nota, freq)

## 3ª Forma Normal — sem dependências transitivas

Ainda há atributos não-chave que dependem de **outro atributo não-chave**:

- em ALUNO: `matricula → curso → coord_curso`
- em TURMA: `turma → disciplina → carga_h` e `turma → professor → titulacao_prof`

Separando de novo:

- **CURSO** (<u>curso</u>, coord_curso)
- **DISCIPLINA** (<u>disciplina</u>, carga_h)
- **PROFESSOR** (<u>professor</u>, titulacao_prof)
- **ALUNO** (<u>matricula</u>, aluno, curso → CURSO)
- **TURMA** (<u>turma</u>, disciplina → DISCIPLINA, professor → PROFESSOR)
- **MATRICULA** (<u>matricula</u> → ALUNO, <u>turma</u> → TURMA, nota, freq)

Esse é exatamente o formato de [`sql/01_schema.sql`](../sql/01_schema.sql) (que acrescenta
departamento e a superclasse pessoa vindas do modelo ER).

## E a coluna `situacao`?

`situacao` depende de `nota` e `frequencia`, que não são chave — seria uma dependência
transitiva e, a rigor, viola a 3FN. Ela é aceitável aqui porque é uma **coluna gerada**:
o próprio banco a calcula, então não existe risco de anomalia de atualização
(ninguém consegue gravar uma situação incoerente com a nota).
