#!/bin/bash

if [ ! -d "$HOME/tc/proton_clang" ]
then
	echo -e "\nCloning clang...\n"
	git clone --single-branch https://github.com/stormbreaker-project/stormbreaker-clang -b 11.x "$HOME"/tc/proton_clang
fi

SECONDS=0
ZIPNAME="lineage-lisa-$(date '+%Y%m%d-%H%M').zip"

export PATH="$HOME/tc/proton_clang/bin:$PATH"
export STRIP="$HOME/tc/proton_clang/aarch64-linux-gnu/bin/strip"
export KBUILD_COMPILER_STRING=$("$HOME"/tc/proton_clang/bin/clang --version | head -n 1 | perl -pe 's/\(http.*?\)//gs' | sed -e 's/  */ /g' -e 's/[[:space:]]*$//')

export ARCH=arm64
export SUBARCH=arm64
export HEADER_ARCH=arm64
export KBUILD_BUILD_HOST=whyredfire
export KBUILD_BUILD_USER=karan

if [[ $1 = "-c" || $1 = "--clean" ]]; then
	rm -rf out
	echo "Cleaned output folder"
fi

mkdir -p out

# make O=out clean && make O=out mrproper
ARCH=arm64 scripts/kconfig/merge_config.sh -O out arch/arm64/configs/vendor/lahaina-qgki_defconfig \
                                                  arch/arm64/configs/vendor/xiaomi_QGKI.config \
                                                  arch/arm64/configs/vendor/lisa_QGKI.config

echo -e "\nStarting compilation...\n"

MAKE_PARAMS="O=out ARCH=arm64 AR=llvm-ar NM=llvm-nm OBJCOPY=llvm-objcopy OBJDUMP=llvm-objdump \
             CC=clang STRIP=llvm-strip CROSS_COMPILE=aarch64-linux-gnu- CROSS_COMPILE_ARM32=arm-linux-gnueabi-"

make -j$(nproc --all) $MAKE_PARAMS || exit $?
make -j$(nproc --all) $MAKE_PARAMS INSTALL_MOD_PATH=modules INSTALL_MOD_STRIP=1 modules_install

kernel="out/arch/arm64/boot/Image"
dtb="out/arch/arm64/boot/dts/vendor/qcom/yupik.dtb"
dtbo="out/arch/arm64/boot/dts/vendor/qcom/lisa-sm7325-overlay.dtbo"

if [ ! -f "$kernel" ] || [ ! -f "$dtb" ] || [ ! -f "$dtbo" ]; then
	echo -e "\nCompilation failed!"
	exit 1
fi

echo -e "\nKernel compiled succesfully! Zipping up...\n"

git clone -q https://github.com/ItsVixano/AnyKernel3 -b lisa-aosp
cp $kernel AnyKernel3
cp $dtb AnyKernel3/dtb
python2 scripts/dtc/libfdt/mkdtboimg.py create AnyKernel3/dtbo.img --page_size=4096 $dtbo
cp $(find out/modules/lib/modules/5.4* -name '*.ko') AnyKernel3/modules/vendor/lib/modules/
cp out/modules/lib/modules/5.4*/modules.{alias,dep,softdep} AnyKernel3/modules/vendor/lib/modules
cp out/modules/lib/modules/5.4*/modules.order AnyKernel3/modules/vendor/lib/modules/modules.load
sed -i 's/\(kernel\/[^: ]*\/\)\([^: ]*\.ko\)/\/vendor\/lib\/modules\/\2/g' AnyKernel3/modules/vendor/lib/modules/modules.dep
sed -i 's/.*\///g' AnyKernel3/modules/vendor/lib/modules/modules.load
rm -rf out/arch/arm64/boot out/modules
cd AnyKernel3
zip -r9 "../$ZIPNAME" * -x .git README.md *placeholder
cd ..
rm -rf AnyKernel3
echo -e "\nCompleted in $((SECONDS / 60)) minute(s) and $((SECONDS % 60)) second(s) !"
echo "Zip: $ZIPNAME"
