
import sys
import numpy as np
from PIL import Image

def read_txt(fname):
    with open(fname, "rt") as txt:
        height, width = 0, 0
        for line in txt.readlines():
            if height>0 and width>0:
                arr = np.zeros([height*width,4], dtype=np.uint8)
                for idx, value in enumerate(line.split()):
                    rgba = [int(value[0:2],16), int(value[2:4],16), int(value[4:6],16), int(value[6:8],16)]
                    arr[idx] = rgba
                return height, width, arr
            if line.startswith("decode result"):
                height, width = 0, 0
                for item in line.split():
                    pair = item.split(':')
                    try:
                        name, value = pair[0].strip(), int(pair[1].strip())
                        if name == "height":
                            height = value
                        elif name == "width":
                            width = value
                    except:
                        pass
    return 0, 0, np.zeros([0], dtype=np.uint8)
        
def read_png(fname):
    img = Image.open(fname)
    width, height = img.size
    if img.mode=="RGB" or img.mode=="RGBA" or img.mode=="P":
        arr = np.asarray(img.convert("RGBA")).reshape([height*width,-1])
        img.close()
        return height, width, arr
    elif img.mode=="L":
        arrl= np.asarray(img).reshape([height*width,-1])
        img.close()
        arr = np.zeros([height*width,4], dtype=np.uint8)
        for i in range(height*width):
            arr[i][0], arr[i][1], arr[i][2], arr[i][3] = arrl[i][0], arrl[i][0], arrl[i][0], 0xff
        return height, width, arr
    else:
        return 0, 0, np.zeros([0], dtype=np.uint8)


# usage python validation.py <png_file>.png <hardware_result>.txt
PNG_FILE = sys.argv[1]
TXT_FILE = sys.argv[2]

h_hw, w_hw, arr_hw = read_txt(TXT_FILE)
h_sw, w_sw, arr_sw = read_png(PNG_FILE)


if h_hw != h_sw or w_hw != w_sw:
    print("** size mismatch,  size1=%dx%d, size2=%dx%d" % (w_hw, h_hw, w_sw, h_sw) )
else:
    print("size1=", arr_hw.shape )
    print("size2=", arr_sw.shape )
    idx = 0
    for (pix_hw, pix_sw) in zip(arr_hw, arr_sw):
        if pix_hw[0]!=pix_sw[0] or pix_hw[1]!=pix_sw[1] or pix_hw[2]!=pix_sw[2] or pix_hw[3]!=pix_sw[3]:
            print("** mismatch at %d   " % (idx,) , pix_hw, pix_sw)
            break
        idx += 1
    else:
        print("total %d pixels validation successful!!" % idx)
