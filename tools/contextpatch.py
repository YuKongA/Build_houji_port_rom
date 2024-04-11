#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
from difflib import SequenceMatcher
from typing import Generator, Any
from re import escape, match

fix_permission = {
    r"/system_ext/lost\+found": "u:object_r:system_file:s0",
    r"/product/lost\+found": "u:object_r:system_file:s0",
    r"/mi_ext/lost\+found": "u:object_r:system_file:s0",
    r"/odm/lost\+found": "u:object_r:vendor_file:s0",
    r"/vendor/lost\+found": "u:object_r:vendor_file:s0",
    r"/vendor_dlkm/lost\+found": "u:object_r:vendor_file:s0",
    r"/system/lost\+found": "u:object_r:rootfs:s0",
    r"/lost\+found": "u:object_r:rootfs:s0",
    "/mi_ext/product/lib*": "u:object_r:system_lib_file:s0",
    "/system/system/app/*": "u:object_r:system_file:s0",
    "/system/system/priv-app/*": "u:object_r:system_file:s0",
    "/system/system/lib*": "u:object_r:system_lib_file:s0",
    "/system/system/bin/apexd": "u:object_r:apexd_exec:s0",
    "/system/system/bin/init": "u:object_r:init_exec:s0",
    "system_ext/lib*": "u:object_r:system_lib_file:s0",
    "/product/lib*": "u:object_r:system_lib_file:s0",
    "/odm/app/*": "u:object_r:vendor_app_file:s0",
    "/odm/etc*": "u:object_r:vendor_configs_file:s0",
    "/vendor/apex*": "u:object_r:vendor_apex_file:s0",
    "/vendor/app/*": "u:object_r:vendor_app_file:s0",
    "/vendor/priv-app/*": "u:object_r:vendor_app_file:s0",
    "/vendor/etc*": "u:object_r:vendor_configs_file:s0",
    "/vendor/firmware*": "u:object_r:vendor_firmware_file:s0",
    "/vendor/framework*": "u:object_r:vendor_framework_file:s0",
    "*/hw/android.hardware.audio*": "u:object_r:hal_audio_default_exec:s0",
    "*/hw/android.hardware.bluetooth*": "u:object_r:hal_bluetooth_default_exec:s0",
    "*/hw/android.hardware.boot*": "u:object_r:hal_bootctl_default_exec:s0",
    "*/hw/android.hardware.power*": "u:object_r:hal_power_default_exec:s0",
    "*/hw/android.hardware.wifi*": "u:object_r:hal_wifi_default_exec:s0",
    "*/bin/idmap": "u:object_r:idmap_exec:s0",
    "*/bin/fsck": "u:object_r:fsck_exec:s0",
    "*/bin/e2fsck": "u:object_r:fsck_exec:s0",
    "*/bin/logcat": "u:object_r:logcat_exec:s0",
    "*/bin/audioserver": "u:object_r:audioserver_exec:s0",
}


def scan_context(file) -> dict:  # 读取context文件返回一个字典
    context = {}
    with open(file, "r", encoding="utf-8") as file_:
        for i in file_.readlines():
            filepath, *other = i.strip().split()
            filepath = filepath.replace(r"\@", "@")
            context[filepath] = other
            if len(other) > 1:
                print(f"[Warn] {i[0]} has too much data.Skip.")
                del context[filepath]
    return context


def scan_dir(folder) -> Generator[Any, Any, Any]:  # 读取解包的目录，返回一个生成器
    part_name = os.path.basename(folder)
    allfiles = [
        "/",
        "/lost+found",
        f"/{part_name}",
        f"/{part_name}/",
        f"/{part_name}/lost+found",
    ]
    for root, dirs, files in os.walk(folder, topdown=True):
        for dir_ in dirs:
            yield os.path.join(root, dir_).replace(folder, "/" + part_name).replace(
                "\\", "/"
            )
        for file in files:
            yield os.path.join(root, file).replace(folder, "/" + part_name).replace(
                "\\", "/"
            )
        for rv in allfiles:
            yield rv


def str_to_selinux(string: str):
    return escape(string).replace("\\-", "-")


def context_patch(fs_file, dir_path) -> tuple:  # 接收两个字典对比
    new_fs = {}
    # 定义已修补过的 避免重复修补
    r_new_fs = {}
    add_new = 0
    print("ContextPatcher: Load origin %d" % (len(fs_file.keys())) + " entries")
    # 定义默认 SeLinux 标签
    if dir_path.endswith("system_dlkm"):
        permission_d = ["u:object_r:system_dlkm_file:s0"]
    elif dir_path.endswith(("odm", "vendor", "vendor_dlkm")):
        permission_d = ["u:object_r:vendor_file:s0"]
    else:
        permission_d = ["u:object_r:system_file:s0"]
    for i in scan_dir(os.path.abspath(dir_path)):
        # 把不可打印字符替换为 *
        if not i.isprintable():
            tmp = ""
            for c in i:
                tmp += c if c.isprintable() else "*"
            i = tmp
        if " " in i:
            i = i.replace(" ", "*")
        i = str_to_selinux(i)
        if fs_file.get(i):
            # 如果已经存在, 直接使用原来的
            new_fs[i] = fs_file[i]
        else:
            permission = None
            # 确认 i 不为空
            if r_new_fs.get(i):
                continue
            if i:
                # 如果路径符合已定义的内容, 直接将 permission 赋值为对应的值
                for f in fix_permission.keys():
                    pattern = f.replace("*", ".*")
                    if i == pattern:
                        permission = [fix_permission[f]]
                        break
                    if match(pattern, i):
                        permission = [fix_permission[f]]
                        break
                # 如果路径不符合已定义的内容, 尝试从 fs_file 中查找相似的路径
                if not permission:
                    for e in fs_file.keys():
                        if (
                            SequenceMatcher(
                                None, (path := os.path.dirname(i)), e
                            ).quick_ratio()
                            >= 0.8
                        ):
                            if e == path:
                                continue
                            permission = fs_file[e]
                            break
                        else:
                            permission = permission_d
            if " " in permission:
                permission = permission.replace(" ", "")
            print(f"Add {i} {permission}")
            add_new += 1
            r_new_fs[i] = permission
            new_fs[i] = permission
    return new_fs, add_new


def main(dir_path, fs_config) -> None:
    new_fs, add_new = context_patch(scan_context(os.path.abspath(fs_config)), dir_path)
    with open(fs_config, "w+", encoding="utf-8", newline="\n") as f:
        f.writelines(
            [i + " " + " ".join(new_fs[i]) + "\n" for i in sorted(new_fs.keys())]
        )
    print("ContextPatcher: Add %d" % add_new + " entries")


def Usage():
    print("Usage:")
    print("%s <folder> <fs_config>" % (sys.argv[0]))
    print("    This script will auto patch file_context")


if __name__ == "__main__":
    import sys

    if len(sys.argv) < 3:
        Usage()
        sys.exit()
    if os.path.isdir(sys.argv[1]) or os.path.isfile(sys.argv[2]):
        main(sys.argv[1], sys.argv[2])
        print("Done!")
    else:
        print(
            "The path or filetype you have given may wrong, please check it wether correct."
        )
        Usage()
