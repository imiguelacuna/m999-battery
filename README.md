# M999Battery

App de barra de menús para macOS que muestra el nivel de batería del **Redragon M999 (K1NG M999 ULT)** cuando se usa con su **dongle 2.4 GHz**. macOS no lo muestra por sí solo en ese modo, porque el dongle se presenta como un teclado y no publica la batería.

```
🖱 84%      🖱 ⚡84%  (cargando)
```

- Solo funciona en **2.4G**. En Bluetooth macOS ya muestra la batería de forma nativa, así que la app se oculta sola.
- Consulta cada 60 s (o con "Actualizar ahora") y se vuelve a mostrar al volver a 2.4G.
- Menú: estado y hora de la última lectura, "Abrir al iniciar sesión" y "Salir".

## Instalar

1. Descarga `M999Battery-<versión>.dmg` desde [Releases](../../releases), ábrelo y haz **doble clic en M999Battery**: la app te ofrecerá copiarse a `/Applications` y se abrirá desde ahí. O **arrástrala al acceso directo Applications** de la ventana del DMG. Si eliges no moverla, funciona igual donde esté.
2. La app no está notarizada. La primera vez macOS la bloqueará: abre **Ajustes del Sistema → Privacidad y seguridad** y pulsa **Abrir de todos modos**, o ejecuta:
   ```bash
   xattr -dr com.apple.quarantine /Applications/M999Battery.app
   ```
3. Concede **Monitorización de entrada**. El dongle se presenta como teclado y macOS exige ese permiso para abrirlo; solo lo puede aprobar el usuario, no se puede automatizar. La app lo pide con el aviso del sistema y, si no queda concedido, muestra un diálogo con un botón que abre el panel correcto (Ajustes del Sistema → Privacidad y seguridad → Monitorización de entrada). Activa M999Battery en la lista; si no aparece, pulsa **+** y elige `M999Battery` en la carpeta Aplicaciones. La app se conecta sola; no hace falta reiniciarla. No registra nada de lo que escribes.
4. Opcional: en el menú, activa **Abrir al iniciar sesión**. Se registra la copia que estés usando, esté donde esté, y la app solo te ofrece moverse a `/Applications` una vez; si eliges "Dejarla aquí", todo funciona igual. Si la mueves tú después, vuelve a activar la opción desde su menú.

Requiere macOS 13 o superior (Apple silicon e Intel).

## Compatibilidad

Probado solo con un **Redragon M999 y su dongle** (USB `0x320F:0x226F`, modo Bluetooth `0x320F:0x22A4`). Otros modelos de Redragon con el mismo chip podrían funcionar, pero no están probados. Si lo pruebas con otro, abre un issue.

## Cómo funciona

El dongle tiene un canal de configuración vendor de 64 bytes (Report ID 4, usage page `0xFF1C`). El software oficial de Redragon para Windows lo usa para leer datos del mouse. La app envía una sola trama de **lectura**:

```
[0]=04  [1..2]=suma16 LE de [3..63]  [3]=1A  [4]=06 (longitud)  [5..6]=0000 (dirección)  resto=0
```

La respuesta trae en `[7]` el estado (0 = OK) y desde `[8]` los datos: `[8]` = batería (%), `[9]` = carga (1 = cargando). Esta app **no envía comandos de escritura** ni toca el modo de actualización de firmware.

El formato salió de analizar el software oficial y se contrastó con el dispositivo real: el byte de carga cambia al poner el mouse en la base, y el de porcentaje bajó de 84 a 83 con el uso. Es un proyecto independiente, **sin relación con Redragon**.

## Compilar desde el código

Solo hace falta Xcode (o las Command Line Tools):

```bash
./build.sh          # compila M999Battery.app (universal) y corre la autoprueba
./build.sh --dmg    # además crea build/M999Battery-<versión>.dmg
open M999Battery.app
```

El DMG se genera con [dmgbuild](https://github.com/dmgbuild/dmgbuild) (`build.sh` lo instala en `.venv`, hace falta Python 3). La ventana y su fondo están en `dmg/`; para cambiar el texto del fondo edita `dmg/make-background.swift` y vuelve a generarlo con `swift dmg/make-background.swift` y `tiffutil -cathidpicheck dmg/background.png dmg/background@2x.png -out dmg/background.tiff`.

`build.sh` firma con una identidad "Apple Development" si existe (así macOS conserva el permiso entre compilaciones) y, si no, con firma ad hoc. Para forzar la firma ad hoc: `SIGN_IDENTITY=- ./build.sh`.

## Publicar una versión

```bash
git tag v1.0.0 && git push origin v1.0.0
```

El workflow [release.yml](.github/workflows/release.yml) compila el DMG y lo adjunta a un Release (si el Release ya existe, no hace nada).

## Licencia

MIT. Ver [LICENSE](LICENSE).
