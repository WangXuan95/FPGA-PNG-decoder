![test](https://img.shields.io/badge/test-passing-green.svg)
![docs](https://img.shields.io/badge/docs-passing-green.svg)
![platform](https://img.shields.io/badge/platform-Quartus|Vivado-blue.svg)


Hard-PNG
===========================
基于**FPGA**的流式的**png**图象解码器



# 特点
* 支持宽度不大于**4000像素**的png图片，对图片高度没有限制。
* **支持所有颜色类型**: 灰度、灰度透明、RGB、索引RGB、RGBA。
* 仅支持**8bit深度**，大多数png图片都是**8bit深度**。
* 完全使用**SystemVerilog**实现，方便移植和仿真。

| ![框图](https://github.com/WangXuan95/Hard-PNG/blob/master/images/blockdiagram.png) |
| :----: |
| **图1** : Hard-PNG 原理框图 |

# 背景知识

**png**是仅次于**jpg**的第二常见的图象压缩格式，相比于**jpg**，**png**支持透明通道，支持无损压缩。在色彩丰富的数码照片中，无损压缩的**png**只能获得**1~4倍**的压缩比，低失真有损压缩的**png**能获得**4~20倍**的压缩比。在色彩较少的人工合成图（例如框图、平面设计）中，无损压缩的**png**就能获得**10倍**以上的压缩比。因此，**png**更适合压缩人工合成图，**jpg**更适合压缩数码照片。

**png** 图片的文件扩展名为 **.png** 。以我们提供的文件 [**test1.png**](https://github.com/WangXuan95/Hard-PNG/blob/master/images/test1.png) 为例，它包含**98字节**，称为**原始码流**。我们可以使用[**WinHex软件**](http://www.x-ways.net/winhex/)查看它：
```
0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, ...... , 0xAE, 0x42, 0x60, 0x82
```
该图象文件解压后只有**4列2行**，共**8个像素**，16进制表示如下表。其中R, G, B, A分别代表像素的**红**、**绿**、**蓝**、**透明**通道。

|          | 列 1 | 列 2 | 列 3 | 列 4 |
| :---:    | :---: | :---: | :---: | :---: |
| **行 1** | R:**FF** G:**F2** B:**00** A:**FF** | R:**ED** G:**1C** B:**24** A:**FF** | R:**00** G:**00** B:**00** A:**FF** | R:**3F** G:**48** B:**CC** A:**FF** |
| **行 2** | R:**7F** G:**7F** B:**7F** A:**FF** | R:**ED** G:**1C** B:**24** A:**FF** | R:**FF** G:**FF** B:**FF** A:**FF** | R:**FF** G:**AE** B:**CC** A:**FF** |

# Hard-PNG 的使用

**Hard-PNG**是一个能够输入**原始码流**，输出**解压后的像素**的硬件模块，它的代码在 [**hard_png.sv**](https://github.com/WangXuan95/Hard-PNG/blob/master/hard_png.sv) 中。其中 **hard_png** 是顶层模块，它的接口如**图2**所示

| ![接口图](https://github.com/WangXuan95/Hard-PNG/blob/master/images/interface.png) |
| :----: |
| **图2** : **hard_png** 接口图 |

它的使用方法很简单，首先需要给 **clk** 信号提供时钟(频率不限)，并将 **rst** 信号置低，解除模块复位。
然后将**原始码流**从**原始码流输入接口** 输入，就可以从**图象基本信息输出接口**和**像素输出接口**中得到解压结果。

以[**test1.png**](https://github.com/WangXuan95/Hard-PNG/blob/master/images/test1.png)为例，我们应该以**图3**的时序把**原始码流**（98个字节）输入**hard_png**中。
该输入接口类似 **AXI-stream** ，其中 **ivalid=1** 时说明外部想发送一个字节给 **hard_png**。**iready=1** 时说明 **hard_png** 已经准备好接收一个字节。只有 **ivalid** 和 **iready** 同时 **=1** 时，**ibyte** 才被成功的输入 **hard_png** 中。

| ![输入时序图](https://github.com/WangXuan95/Hard-PNG/blob/master/images/wave1.png) |
| :----: |
| **图3** : **hard_png** 输入时序图，以 **test1.png** 为例 |

在输入的同时，解压结果从模块中输出，如**图4**。在新的一帧图象输出前，**newframe** 信号会出现一个时钟周期的高电平脉冲，同时 **colortype, width, height** 保持有效直到该图象的所有像素输出完为止。其中 **width, height** 分别为图象的宽度和高度， **colortype** 的含义如下表。另外， **ovalid=1** 代表该时钟周期有一个像素输出，该像素的R,G,B,A通道分别出现在 **opixelr,opixelg,opixelb,opixela** 信号上。

| colortype | 2'd0 | 2'd1 | 2'd2 | 2'd3 |
| :-------: | :--: | :--: | :--: | :--: |
| **颜色类型** | 灰度图 | 灰度+透明 | RGB / 索引RGB | RGBA |
| **含义** | RGB通道相等, A通道=0xFF | RGB通道相等 | RGB通道不等, A通道=0xFF | RGBA通道均不等 |

| ![输出时序图](https://github.com/WangXuan95/Hard-PNG/blob/master/images/wave2.png) |
| :----: |
| **图4** : **hard_png** 输出时序图，以 **test1.png** 为例 |

当一个图象完全输入结束后，我们可以紧接着输入下一个图象进行解压。如果一个图象输入了一半，我们想打断当前解压进程并输入下一个图象，则需要将 **rst** 信号拉高至少一个时钟周期进行复位。


# 仿真

[**tb_hard_png.sv**](https://github.com/WangXuan95/Hard-PNG/blob/master/tb_hard_png.sv) 是仿真的顶层，它从指定的 **.png** 文件中读取**原始码流**输入[**hard_png**](https://github.com/WangXuan95/Hard-PNG/blob/master/hard_png.sv)中，再接收**解压后的像素**并写入一个 **.txt** 文件。

仿真前，请将 [**tb_hard_png.sv**](https://github.com/WangXuan95/Hard-PNG/blob/master/tb_hard_png.sv) 中的**PNG_FILE宏名**改为 **.png** 文件的路径，将**OUT_FILE宏名**改为 **.txt** 文件的路径。然后运行仿真。 **.png** 文件越大，仿真的时间越长。当**ivalid**信号出现下降沿时，仿真完成。然后你可以从 **.txt** 文件中查看解压结果。

我们在 [**images文件夹**](https://github.com/WangXuan95/Hard-PNG/blob/master/images) 下提供了多个 **.png** 文件，它们尺寸各异，且有不同的颜色类型，你可以用它们进行仿真。以 [**test3.png**](https://github.com/WangXuan95/Hard-PNG/blob/master/images/test3.png) 为例，仿真得到的 **.txt** 文件如下：
```
frame  type:2  width:83  height:74 
f4d8c3ff f4d8c3ff f4d8c3ff f4d8c3ff f4d8c3ff f4d9c3ff ......
```
这代表图片的尺寸是**83x74**， **colortype** 是2（RGB），第1行第1列的像素是RGBA=(0xf4, 0xd8, 0xc3, 0xff)，第1行第2列的像素是RGBA=(0xf4, 0xd8, 0xc3, 0xff)，......

# 正确性验证

为了验证解压结果是否正确，我们提供了**Python**程序 [**validation.py**](https://github.com/WangXuan95/Hard-PNG/blob/master/validation.py) ，它对 **.png** 文件进行软件解压，并与仿真得到的 **.txt** 文件进行比较，若比较结果相同则验证通过。为了准备必要的运行环境，请安装**Python3**以及其配套的 [**numpy**](https://pypi.org/project/numpy/) 和 [**PIL**](https://pypi.org/project/Pillow/) 库。运行环境准备好后，打开 [**validation.py**](https://github.com/WangXuan95/Hard-PNG/blob/master/validation.py) ，将变量 **PNG_FILE** 改为要验证的 **.png** 文件的路径，将 **TXT_FILE** 改为仿真输出的 **.txt** 文件的路径，然后用命令运行它：
```
python validation.py
```
若验证通过，则打印 **"validation successful!!"** 。目前我们测试了几十张不同的 **.png** 图片，均验证通过。

# 性能测试

* **测试平台**: 在 Altera Cyclone IV EP4CE40F23C6 上运行 **Hard-PNG** 进行**png**解压，时钟频率= **50MHz** （正好时序收敛）。
* **对比平台**: 使用**MSVC++编译器**以**O3优化级别**编译[**upng库**](https://github.com/elanthis/upng)，在笔记本电脑（**Intel Core I7 8750H**）上运行**png**解压。

测试结果如下表，**Hard-PNG**的性能接近对比平台。由此可以推断，**Hard-PNG**的性能好于大部分**ARM嵌入式处理器**。

| **png文件名** | **颜色类型** | **图象尺寸** | **对比平台耗时** | **Hard-PNG 耗时** |
| :-----------: | :----------: | :----------: | :--------------: | :---------------: |
|   test9.png   |     RGB      |   631x742    |      83 ms       |      204 ms       |
|  test10.png   |   索引RGB    |   631x742    |      不支持      |       48 ms       |
|  test11.png   |     RGBA     |  1920x1080   |      402 ms      |      993 ms       |
|  test12.png   |   索引RGB    |  1920x1080   |      不支持      |      204 ms       |
|  test13.png   |     RGB      |  1819x1011   |      321 ms      |      655 ms       |
|  test14.png   |     黑白     |  1819x1011   |      135 ms      |      227 ms       |
|   wave2.png   |   索引RGB    |   1427x691   |      不支持      |       27 ms       |


# FPGA 资源消耗

下表是**hard_png模块**综合后占用的FPGA资源量。

|           **FPGA 型号**            | LUT  | LUT(%) |  FF  | FF(%) | Logic | Logic(%) |  BRAM   | BRAM(%) |
| :--------------------------------: | :--: | :----: | :--: | :---: | :---: | :------: | :-----: | :-----: |
|     **Xilinx Artix-7 XC7A35T**     | 2581 |  13%   | 2253 |  5%   |   -   |    -     | 792kbit |   44%   |
| **Altera Cyclone IV EP4CE40F23C6** |  -   |   -    |  -   |   -   | 4551  |   11%    | 427kbit |   37%   |




# 参考链接

感谢以下链接为我们提供参考。

* [**upng**](https://github.com/elanthis/upng): 一个轻量化的 C 语言 **png** 解码库
* [**TinyPNG**](https://tinypng.com/): 一个利用索引 RGB 对 **png** 图片进行有损压缩的工具
* [**PNG Specification**](https://www.w3.org/TR/REC-png.pdf): **png** 标准手册
