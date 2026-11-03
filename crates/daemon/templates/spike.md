---
name: Spike / investigação
description: Pergunta, hipóteses e experimentos curtos que terminam numa decisão.
---
# Spike

A pergunta que este spike responde, em uma frase.

## Pergunta e critério de decisão {#pergunta}
<!-- prompt: A pergunta, o que decide e quanto tempo vale gastar. -->
- Pergunta: a definir
- Decide quando: a definir
- Limite de tempo: 2 dias

## Hipóteses
<!-- prompt: Hipóteses testáveis, cada uma com o sinal que a confirma ou derruba. -->
| Hipótese | Sinal | Resultado |
|---|---|---|
| a definir | a definir | pendente |

## Execução
```loops
- title: Experimentos
  model: sonnet
  tasks:
    - {id: T1, title: Protótipo A, skill: a-definir, model: sonnet, group: 1}
    - {id: T2, title: Protótipo B, skill: a-definir, model: sonnet, group: 1}
    - {id: T3, title: Comparar e recomendar, skill: a-definir, model: opus, group: 2, after: [T1, T2]}
```

## Decisão
<!-- prompt: A recomendação, o que foi descartado e por quê. Vira ADR se for aceita. -->
A preencher depois dos experimentos.
