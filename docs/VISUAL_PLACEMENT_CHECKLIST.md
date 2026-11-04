# MZ Props — checklist do placement visual

O fluxo administrativo fica em:

```text
/admin > Mundo e cenários > Props persistentes
```

O `mz_menu` apresenta o assistente, o `mz_world_editor` controla somente o
fantasma local e o `mz_props` valida e persiste o resultado.

## Controles

- `E`: confirma a posição;
- `BACKSPACE`: cancela e remove o fantasma;
- `W/A/S/D`: move o fantasma livremente sem deslocar o personagem;
- mouse: orbita a câmera ao redor do objeto;
- scroll: aproxima ou afasta a câmera;
- setas esquerda/direita: giram;
- `SHIFT`: acelera movimento, giro e altura;
- segure `PAGE UP/PAGE DOWN`: ajusta a altura continuamente;
- `R`: encaixa uma vez no ponto central da mira.

Durante o placement, o ped fica temporariamente imobilizado. O estado anterior
de congelamento é preservado e restaurado ao confirmar, cancelar ou parar o
resource.

A câmera usada no placement é temporária e acompanha o objeto. Ao confirmar,
cancelar ou parar o resource, ela é destruída e o gameplay volta para a câmera
normal.

## Checklist

- [ ] modelo inválido é recusado antes do placement;
- [ ] veículo ou ped não pode ser usado como prop;
- [ ] o fantasma não possui colisão;
- [ ] o raycast não colide com o próprio fantasma;
- [ ] cancelar remove o fantasma e invalida o rascunho;
- [ ] confirmar mostra nome, código, modelo, coordenadas e heading;
- [ ] criação distante mais de 35 metros é recusada pelo servidor;
- [ ] código duplicado é recusado;
- [ ] prop nasce apenas uma vez depois da confirmação;
- [ ] restart não duplica entidades;
- [ ] `stream_distance` cria e remove o prop com histerese;
- [ ] `stream_distance` também define o LOD visual do objeto, sem desaparecer no limite original do modelo;
- [ ] valores entre 10 e 2000 metros são preservados; acima disso são limitados por segurança;
- [ ] editar congelamento, colisão, visibilidade e streaming sincroniza clients;
- [ ] arquivar remove o prop sem apagar a linha;
- [ ] restaurar volta a transmitir o prop;
- [ ] ator e ação aparecem no log detalhado.

Permissões usadas:

```text
staff.world.view
staff.world.props.create
staff.world.props.manage
staff.world.props.archive
```
