// zero_copy_bench.cc — 文档 §8「零拷贝 + 多核 + 高优先级」极限压测
// 对应 hannahrepo/rk3588-npu 的 main.cc；本版按本机 SDK(2.3.2) 头文件语义实现。
//
// 板端编译（本板原生 g++，无需交叉工具链）：
//   g++ -O2 zero_copy_bench.cc -o zero_copy_bench \
//       -I/usr/local/include/rknn -lrknnrt -lpthread $(pkg-config --cflags --libs opencv4)
//
// 用法：./zero_copy_bench model.rknn image.jpg [秒数] [pass_through 0|1] [线程数]
//   pass_through=1（默认，文档 §8.3 的做法）：
//       buf 数据不做任何转换直接送进模型输入节点 —— 必须自己把图量化成 INT8。
//       本模型 zp=-128、scale=0.003922(≈1/255)，故 quant = uint8 - 128。
//   pass_through=0（官方 rknn_create_mem_demo 的做法）：
//       按 type/fmt 转换，喂 UINT8 原图，归一化+量化由 NPU 顺带完成。
#include "rknn_api.h"

#include <atomic>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <thread>
#include <vector>

#include <opencv2/opencv.hpp>

#define NUM_CORES 3
#define DEF_THREADS 8
#define DEF_SECONDS 20
#define DEF_WARMUP  5   // 预热秒数，不计入统计（方案 §五.3）

static double read_sys_freq_hz(const char* path) {
  FILE* f = fopen(path, "r");
  if (!f) return -1.0;
  long long v = -1;
  if (fscanf(f, "%lld", &v) != 1) v = -1;
  fclose(f);
  return (double)v;
}

static unsigned char* load_model(const char* path, int* size) {
  FILE* fp = fopen(path, "rb");
  if (!fp) { printf("fopen %s fail!\n", path); return nullptr; }
  fseek(fp, 0, SEEK_END);
  long len = ftell(fp);
  fseek(fp, 0, SEEK_SET);
  unsigned char* m = (unsigned char*)malloc(len);
  if ((long)fread(m, 1, len, fp) != len) { free(m); fclose(fp); return nullptr; }
  fclose(fp);
  *size = (int)len;
  return m;
}

int main(int argc, char** argv) {
  if (argc < 3) {
    printf("Usage: %s model.rknn image.jpg [seconds] [pass_through 0|1] [threads] [warmup_s]\n", argv[0]);
    return -1;
  }
  const char* model_path = argv[1];
  const char* image_path = argv[2];
  int   seconds     = argc > 3 ? atoi(argv[3]) : DEF_SECONDS;
  int   pass_through = argc > 4 ? atoi(argv[4]) : 1;
  int   num_threads  = argc > 5 ? atoi(argv[5]) : DEF_THREADS;
  int   warmup       = argc > 6 ? atoi(argv[6]) : DEF_WARMUP;
  if (num_threads < 1) num_threads = 1;
  if (warmup < 0) warmup = 0;

  int model_size = 0;
  unsigned char* model = load_model(model_path, &model_size);
  if (!model) return -1;

  // ---- 读图（只做一次，压测循环里不再碰 CPU 图像处理）----
  cv::Mat img = cv::imread(image_path, cv::IMREAD_COLOR);
  if (img.empty()) { printf("imread %s fail!\n", image_path); return -1; }
  cv::cvtColor(img, img, cv::COLOR_BGR2RGB);

  printf("=========================================================\n");
  printf(" 零拷贝极限压测  (文档 §8)\n");
  printf(" 模型: %s (%d bytes)\n", model_path, model_size);
  printf(" 线程: %d   核心: %d   预热: %ds   计时: %ds   pass_through: %d\n",
         num_threads, NUM_CORES, warmup, seconds, pass_through);
  printf("=========================================================\n");

  rknn_context  ctxs[NUM_CORES];
  rknn_tensor_mem* input_mems[NUM_CORES];
  rknn_core_mask core_masks[NUM_CORES] = {RKNN_NPU_CORE_0, RKNN_NPU_CORE_1, RKNN_NPU_CORE_2};

  for (int i = 0; i < NUM_CORES; i++) {
    int ret = rknn_init(&ctxs[i], model, model_size, RKNN_FLAG_PRIOR_HIGH, NULL);
    if (ret < 0) { printf("rknn_init core%d fail! ret=%d\n", i, ret); return -1; }
    ret = rknn_set_core_mask(ctxs[i], core_masks[i]);
    if (ret < 0) { printf("rknn_set_core_mask core%d fail! ret=%d\n", i, ret); return -1; }

    rknn_tensor_attr in;
    memset(&in, 0, sizeof(in));
    in.index = 0;
    ret = rknn_query(ctxs[i], RKNN_QUERY_INPUT_ATTR, &in, sizeof(in));
    if (ret < 0) { printf("rknn_query INPUT_ATTR core%d fail! ret=%d\n", i, ret); return -1; }

    if (i == 0) {
      printf(" 输入张量: dims=[%d,%d,%d,%d] fmt=%s type=%s zp=%d scale=%f w_stride=%d\n",
             in.dims[0], in.dims[1], in.dims[2], in.dims[3],
             get_format_string(in.fmt), get_type_string(in.type),
             in.zp, in.scale, in.w_stride);
    }

    int H = in.dims[1], W = in.dims[2], C = in.dims[3];
    if (img.cols != W || img.rows != H) cv::resize(img, img, cv::Size(W, H));

    if (pass_through) {
      in.type = RKNN_TENSOR_INT8;   // 数据已是模型要的量化格式
      in.fmt  = RKNN_TENSOR_NHWC;
    } else {
      in.type = RKNN_TENSOR_UINT8;  // 交给 NPU 做归一化+量化
      in.fmt  = RKNN_TENSOR_NHWC;
    }
    in.pass_through = pass_through;

    input_mems[i] = rknn_create_mem(ctxs[i], in.size_with_stride);

    // 按 w_stride 逐行填充（本模型 w_stride==W，走快路径）
    int stride = in.w_stride ? in.w_stride : W;
    if (pass_through) {
      int8_t* dst = (int8_t*)input_mems[i]->virt_addr;
      for (int h = 0; h < H; h++) {
        const uint8_t* src = img.ptr<uint8_t>(h);
        for (int w = 0; w < W * C; w++) dst[h * stride * C + w] = (int8_t)(src[w] - 128);
      }
    } else {
      for (int h = 0; h < H; h++)
        memcpy((uint8_t*)input_mems[i]->virt_addr + (size_t)h * stride * C,
               img.ptr<uint8_t>(h), (size_t)W * C);
    }

    ret = rknn_set_io_mem(ctxs[i], input_mems[i], &in);
    if (ret < 0) { printf("rknn_set_io_mem core%d fail! ret=%d\n", i, ret); return -1; }
  }

  // ---- 预热 ----
  for (int i = 0; i < NUM_CORES; i++)
    for (int w = 0; w < 3; w++) rknn_run(ctxs[i], NULL);

  // ---- 多线程压测：输入已在共享内存，rknn_run 传 NULL ----
  std::atomic<uint64_t> total_frames(0);
  std::atomic<bool>     stop(false);
  std::atomic<bool>     counting(false);
  std::vector<uint64_t> per_thread(num_threads, 0);

  std::vector<std::thread> workers;
  workers.reserve(num_threads);
  for (int t = 0; t < num_threads; t++) {
    workers.emplace_back([&, t]() {
      rknn_context ctx = ctxs[t % NUM_CORES];
      uint64_t n = 0;
      while (!stop.load(std::memory_order_relaxed)) {
        if (rknn_run(ctx, NULL) < 0) break;
        if (counting.load(std::memory_order_relaxed)) n++;   // 预热期只跑不计数
      }
      per_thread[t] = n;
      total_frames.fetch_add(n, std::memory_order_relaxed);
    });
  }

  std::this_thread::sleep_for(std::chrono::seconds(warmup));   // 预热：填充流水线
  counting.store(true);
  auto t_start = std::chrono::steady_clock::now();
  std::this_thread::sleep_for(std::chrono::seconds(seconds));
  counting.store(false);
  double elapsed = std::chrono::duration<double>(
                       std::chrono::steady_clock::now() - t_start).count();
  stop.store(true);
  for (auto& w : workers) w.join();

  double fps = (double)total_frames.load() / elapsed;
  double avg_latency = (1000.0 * num_threads) / (fps * NUM_CORES);  // 文档 §8.3 的算法

  printf("\n----------------- 结果 -----------------\n");
  printf(" 总帧数      : %llu\n", (unsigned long long)total_frames.load());
  printf(" 墙钟耗时    : %.2f s\n", elapsed);
  printf(" >>> 吞吐    : %.1f fps\n", fps);
  printf(" 平均单核延迟: %.2f ms  (文档 §8.3 算法)\n", avg_latency);
  printf(" 线程分布    :");
  for (int t = 0; t < num_threads; t++) printf(" c%d:%llu", t % NUM_CORES, (unsigned long long)per_thread[t]);
  printf("\n");
  double npu = read_sys_freq_hz("/sys/class/devfreq/fdab0000.npu/cur_freq");
  double ddr = read_sys_freq_hz("/sys/class/devfreq/dmc/cur_freq");
  printf(" NPU 频率    : %.0f Hz (%.2f GHz)\n", npu, npu / 1e9);
  printf(" DDR 频率    : %.0f Hz (%.0f MHz)\n", ddr, ddr / 1e6);
  printf("RESULT threads=%d warmup=%d seconds=%d frames=%llu elapsed=%.3f fps=%.2f\n",
         num_threads, warmup, seconds, (unsigned long long)total_frames.load(), elapsed, fps);
  printf("---------------------------------------\n");

  // ---- 输出正确性校验：单次推理，打印各输出张量的 int8 校验和 ----
  // 用途：pass_through=0（NPU 做量化）与 pass_through=1（自己量化成 INT8）
  //       两条路径若校验和一致，即证明手写的 quant = uint8 - 128 正确。
  {
    rknn_input_output_num ionum;
    if (rknn_query(ctxs[0], RKNN_QUERY_IN_OUT_NUM, &ionum, sizeof(ionum)) == RKNN_SUCC) {
      std::vector<rknn_output> outs(ionum.n_output);
      memset(outs.data(), 0, sizeof(rknn_output) * ionum.n_output);
      for (uint32_t i = 0; i < ionum.n_output; i++) outs[i].want_float = 0;
      if (rknn_run(ctxs[0], NULL) == 0 &&
          rknn_outputs_get(ctxs[0], ionum.n_output, outs.data(), NULL) == 0) {
        printf("CHECKSUM");
        for (uint32_t i = 0; i < ionum.n_output; i++) {
          const int8_t* p = (const int8_t*)outs[i].buf;
          long long s = 0; uint32_t nz = 0;
          for (uint32_t k = 0; k < outs[i].size; k++) { s += p[k]; if (p[k]) nz++; }
          printf(" out%u_size=%u out%u_sum=%lld out%u_nz=%u", i, outs[i].size, i, s, i, nz);
        }
        printf("\n");
        rknn_outputs_release(ctxs[0], ionum.n_output, outs.data());
      }
    }
  }
  printf("---------------------------------------\n");

  for (int i = 0; i < NUM_CORES; i++) {
    rknn_destroy_mem(ctxs[i], input_mems[i]);
    rknn_destroy(ctxs[i]);
  }
  free(model);
  return 0;
}
