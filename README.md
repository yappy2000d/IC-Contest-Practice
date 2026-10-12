# IC Contest Practice

Personal solutions and practice notes for past problems of the National University IC Design Contest (Taiwan), implemented in Verilog HDL.

> **Note:** This repository does **not** include the official problem specifications or test data. Please download them from the official contest website and use them alongside the code provided here.

## Obtaining the Problem Sets

Past problems are published on the [Past Problems page](https://proj.moe.edu.tw/moeisoc/cl.aspx?n=4526) of the Ministry of Education's Smart Chip Systems and Applications program. The page is organized by contest category:

| Code | Category (Chinese) | Category (English) |
| ---- | ------------------ | ------------------ |
| A | 研究所全客戶設計組 | Graduate, Full-Custom Design |
| B | 研究所標準元件數位電路設計組 | Graduate, Cell-Based Digital Design |
| C | 類比電路設計組 | Analog Circuit Design |
| D | 大學全客戶設計組 | Undergraduate, Full-Custom Design |
| E | 大學標準元件數位電路設計組 | Undergraduate, Cell-Based Digital Design |

1. Open the page above and select the category that matches the problem you want to practice.
2. Download the problem package for the corresponding year and extract it.
3. Place the specification (PDF) and testbench files in the matching directory.

> The availability of older editions (for example, 2005 and 2008) may vary. If a package is missing, please check the archives of the organizing institution for that year.

## Naming Convention

Each problem directory is named as follows:

```
<year>_<category>_<round>
```

| Field      | Values                                                                 |
| ---------- | ---------------------------------------------------------------------- |
| `year`     | Year of the contest edition (e.g., `2022`)                             |
| `category` | `grad` = graduate, `univ` = undergraduate, `all` = open to all categories |
| `round`    | `pre` = preliminary                                                    |

For example, `2022_univ_pre` refers to the 2022 undergraduate preliminary problem. Designs that do not belong to a specific contest edition are placed in `others/`.

## Synthesis Results

All eight designs pass functional simulation and have been synthesized. Results are from my own runs and are provided for reference only. Rows in **bold** mark the designs I consider particularly strong in terms of Area × Time.

| Directory       | Problem                                                       | Clock Period (ns) | Area (µm²) | Sim Time (ns) |
| --------------- | ------------------------------------------------------------- | ----------------: | ---------: | ------------: |
| `2005_all_pre`  | Approximate Average Generator (近似平均值產生器)                |               8   |  16,635.00 |     16,024.00 |
| `2008_grad_pre` | Image Display Controller (影像顯示控制)                         |              16   |  48,184.09 |     52,905.00 |
| **`2015_grad_pre`** | **Set Coverage Counter (指定集合內覆蓋之元素個數計數器)**     |           **9.1** |   **5,665.92** |     **38,483.90** |
| **`2016_grad_pre`** | **Local Binary Pattern, LBP (局部二值模式)**                |           **3**   |   **7,171.51** |    **145,179.00** |
| **`2018_univ_pre`** | **Image Display Controller (影像顯示控制)**                 |          **10**   |  **57,501.12** |      **2,246.17** |
| **`2019_univ_pre`** | **Image Convolution Circuit (圖像卷積電路設計)**            |          **10**   |  **46,759.98** |    **220,251.14** |
| `2021_univ_pre` | Geofence System (地理圍籬系統)                                  |              30   |  71,660.83 |     22,650.00 |
| `2022_univ_pre` | Job Assignment Machine, JAM (派工機)                           |               8   |   9,597.10 |  1,199,396.00 |

**Metrics**

- **Clock Period**: clock cycle time used for synthesis and simulation.
- **Area**: total cell area reported by Design Compiler.
- **Sim Time**: total simulation time to complete the test pattern.

**Synthesis setup:** Synopsys Design Compiler 2026.03, `CBDK_IC_Contest_v2.5` cell library (TSMC 0.13 µm, slow corner, `slow.db`).

## Other Designs

The `others/` directory contains designs that are not part of the problem sets above. Synthesis setup is identical to that described in [Synthesis Results](#synthesis-results). Rows in **bold** mark the designs I consider particularly strong in terms of Area × Time.

<!-- Adjust the paths to match the actual directory names. -->

| Directory    | Design              | Clock Period (ns) | Area (µm²) | Sim Time (ns) |
| ------------ | ------------------- | ----------------: | ---------: | ------------: |
| `others/CTE` | CTE (色彩轉換)       |               TBD |        TBD |           TBD |
| **`others/MFE`** | **MFE (中值濾波)** |          **2.25** |  **49,166.00** |     **32,715.00** |

The `others/` directory contains additional designs that are not part of the preliminary problem sets above.

## Contents of Each Problem Directory

<!-- Adjust the paths to match the actual directory names. -->

- RTL design sources (`.v`)
- Custom testbenches (if any)
- Synthesis scripts and reports (if any)

## Requirements

- **Language:** Verilog HDL
- **Synthesis:** Synopsys Design Compiler 2026.03
- **Cell library:** `CBDK_IC_Contest_v2.5` (slow corner, `slow.db`)
- **Simulation:** Synopsys VCS 2026.03

## Disclaimer

- This repository is intended for personal study and practice only. The solutions are not guaranteed to be optimal or fully correct.
- All problem statements and test data are the property of the contest organizers and are intentionally excluded from this repository. Please obtain them from the official source.
- Attempting each problem independently before consulting these solutions is recommended.

## License

This project is distributed under the terms of the [LICENSE](./LICENSE) file.
