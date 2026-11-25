# 1. Modelo conceitual (ER estendido) e mapeamento para o relacional

## Minimundo

Uma universidade é organizada em **departamentos**. Cada departamento oferece **cursos** e
**disciplinas** e tem **professores** lotados nele. Professores e alunos são **pessoas**
(ninguém é as duas coisas ao mesmo tempo). Cada curso é coordenado por um professor.
Disciplinas podem exigir outras como **pré-requisito**. A cada semestre, disciplinas são
ofertadas em **turmas**, ministradas por um professor, nas quais os alunos se **matriculam**;
ao fim do semestre cada matrícula recebe nota e frequência.

## Diagrama ER

```mermaid
erDiagram
    DEPARTAMENTO ||--o{ CURSO : oferece
    DEPARTAMENTO ||--o{ DISCIPLINA : oferece
    DEPARTAMENTO ||--o{ PROFESSOR : "tem lotado"
    PESSOA ||--o| PROFESSOR : "é um"
    PESSOA ||--o| ALUNO : "é um"
    PROFESSOR |o--o| CURSO : coordena
    CURSO ||--o{ ALUNO : "tem"
    DISCIPLINA ||--o{ PRE_REQUISITO : exige
    DISCIPLINA ||--o{ PRE_REQUISITO : "é exigida"
    DISCIPLINA ||--o{ TURMA : "é ofertada em"
    PROFESSOR ||--o{ TURMA : ministra
    ALUNO ||--o{ MATRICULA : faz
    TURMA ||--o{ MATRICULA : recebe

    PESSOA {
        int id PK
        varchar nome
        varchar email UK
        date data_nascimento
    }
    PROFESSOR {
        int pessoa_id PK, FK
        char siape UK
        varchar titulacao
        numeric salario
        date data_admissao
    }
    ALUNO {
        int pessoa_id PK, FK
        char matricula UK
        smallint ano_ingresso
    }
    DEPARTAMENTO {
        int id PK
        varchar sigla UK
        varchar nome
    }
    CURSO {
        int id PK
        varchar codigo UK
        varchar nome
    }
    DISCIPLINA {
        int id PK
        varchar codigo UK
        varchar nome
        smallint carga_horaria
    }
    PRE_REQUISITO {
        int disciplina_id PK, FK
        int requisito_id PK, FK
    }
    TURMA {
        int id PK
        smallint ano
        smallint semestre
        char codigo
        smallint vagas
    }
    MATRICULA {
        int aluno_id PK, FK
        int turma_id PK, FK
        numeric nota
        numeric frequencia
        varchar situacao "derivado"
    }
```

## Decisões de modelagem

| Conceito do ER | Onde aparece | Como foi mapeado |
|---|---|---|
| **Especialização total e disjunta** | `PESSOA` → `PROFESSOR`, `ALUNO` | Uma tabela por classe; a PK da subclasse é FK para `pessoa`. A disjunção é garantida por trigger (`fn_especializacao_disjunta`). |
| **Relacionamento 1:N** | departamento–curso, curso–aluno, professor–turma… | FK no lado N. |
| **Relacionamento 1:1 parcial** | professor *coordena* curso | FK `coordenador_id` com `UNIQUE` em `curso` (o lado que sempre tem coordenador). |
| **Relacionamento N:N com atributos** | aluno *matricula-se em* turma | Tabela própria `matricula`, PK composta `(aluno_id, turma_id)` e atributos `nota`, `frequencia`. |
| **Auto-relacionamento N:N** | disciplina *é pré-requisito de* disciplina | Tabela `pre_requisito` com duas FKs para `disciplina` e `CHECK` impedindo auto-referência. |
| **Atributo derivado** | situação da matrícula | Coluna gerada (`GENERATED ALWAYS AS ... STORED`) a partir de nota e frequência. |
| **Entidade fraca (conceitualmente)** | turma depende de disciplina | Chave natural `UNIQUE (disciplina_id, ano, semestre, codigo)`; usamos `id` substituto para simplificar as FKs. |

## Restrições de integridade

- **De domínio** (`CHECK`): nota entre 0 e 10, frequência entre 0 e 100, semestre ∈ {1, 2},
  titulação ∈ {Graduado, Mestre, Doutor}, carga horária múltipla de 15, formato de e-mail, SIAPE e matrícula.
- **De chave** (`PRIMARY KEY`, `UNIQUE`): e-mail, SIAPE, matrícula, códigos de curso e disciplina.
- **Referencial** (`FOREIGN KEY`): com `ON DELETE CASCADE` onde a linha dependente não faz sentido sozinha
  (subclasses, matrículas) e `ON DELETE SET NULL` para o coordenador.
- **Semânticas** (triggers): turma lotada, pré-requisitos e especialização disjunta.
