---
title: Metodología
---

# Metodología, fuentes y límites

## De dónde salen los números

- **Casos:** dataset del SNVS 2.0, Ministerio de Salud de la Nación, licencia CC-BY 4.0: [Vigilancia de infecciones respiratorias agudas](https://datos.salud.gob.ar/dataset/vigilancia-de-infecciones-respiratorias-agudas) (enfermedad tipo influenza, bronquiolitis en menores de 2 años y neumonía). Los archivos se publican en ventanas que se superponen y algunos años se republicaron varias veces con cifras distintas: para cada año se usa la última publicación.
- **Población:** [Estructura de población identificada](https://datos.gob.ar/dataset/renaper-estructura-poblacion-argentina), RENAPER, CC-BY 4.0. Es población con DNI, no una proyección del INDEC.
- **Geografía:** códigos de departamento y provincia de [Georef](https://datosgobar.github.io/georef-ar-api/). Contornos provinciales de [Natural Earth](https://www.naturalearthdata.com/) (dominio público).
- **Actualización:** una vez por semana se busca si hay archivos nuevos o modificados; si no los hay, el sitio no se reconstruye.

## Cómo se calcula

- **Tasa:** casos del período cada 100.000 habitantes, usando el corte de población más cercano al año.
- **Eventos respiratorios:** bronquiolitis y neumonía se suman entre ambulatorios, internados y sin especificar. Esa apertura solo existe en las publicaciones más recientes y se usa para medir la proporción de internados.
- **Año en curso:** el último año está incompleto. El sitio abre por defecto en el último año, aunque sea parcial, y lo marca como tal.
- **COVID-19 (marzo de 2020 a febrero de 2022):** los cuadros respiratorios se notificaron en buena parte como sospecha de COVID-19, que no está en este dataset, y además circularon menos la influenza y el virus sincicial. Los casos de esos años están subestimados y casi no hay brotes; además, 2020-2021 bajan el corredor de 2022 a 2025.
- **Tasas con pocos casos:** una provincia con menos de 20 casos tiene una tasa inestable; el gráfico la muestra atenuada.
- **Corredor endémico:** percentiles 25, 50 y 75 de la misma semana en los 5 años previos, por provincia y evento. No incluye el año evaluado. Los años con menos de 5 años de historia usan los que haya.
- **Brote:** racha de semanas consecutivas por encima del percentil 75. Una semana sin base histórica no cuenta como brote.
- **Código y pruebas:** todo el procesamiento es SQL versionado con dbt. La [documentación del modelo de datos](https://datakrdo.github.io/vigilancia-respiratoria-ar/dbt/) incluye el linaje completo.

## Qué no dice este sitio

- **Residencia, no contagio.** Los casos se asignan al departamento de residencia, que puede no ser donde la persona se infectó.
- **Las últimas semanas están incompletas.** Las notificaciones llegan con demora; ver el hallazgo sobre [retraso de notificación](./hallazgos#retraso-de-notificacion).
- **CABA se publica por ciudad.** RENAPER informa la población de CABA completa, no por comuna: las comunas aparecen sin tasa.
- **Sin apertura por edad.** Los conteos pequeños por departamento, edad y semana podrían identificar personas, por eso este sitio publica solo agregados por departamento o provincia.
- **La notificación no es pareja.** Algunas jurisdicciones notifican mucho menos que otras al SNVS 2.0: Santa Fe pasó de 322 casos de ETI cada 100.000 en 2019 a 52 en 2025, y CABA de 815 a 240, mientras Córdoba está en 3.379. Una tasa baja puede ser poca notificación y no poca enfermedad; compará cada provincia con su propia historia antes que con las demás.
- **Notificado no es confirmado.** Las cifras son casos notificados al sistema, con criterios que pueden variar entre jurisdicciones y años.
