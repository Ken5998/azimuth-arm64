/* Checks VK_EXT_external_memory_host on the Turnip driver picked by VK_DRIVER_FILES. */
#define VK_NO_PROTOTYPES
#include <vulkan/vulkan.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/mman.h>

#define CHECK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { printf("FAIL: %s -> %d\n", #x, r_); return 1; } } while (0)

static PFN_vkGetInstanceProcAddr gipa;
#define IFN(name) PFN_##name name = (PFN_##name)gipa(inst, #name)
#define DFN(name) PFN_##name name = (PFN_##name)vkGetDeviceProcAddr(dev, #name)

int main(void)
{
   void *lib = dlopen("libvulkan.so.1", RTLD_NOW);
   if (!lib) { printf("FAIL: libvulkan.so.1 not found\n"); return 1; }
   gipa = (PFN_vkGetInstanceProcAddr)dlsym(lib, "vkGetInstanceProcAddr");
   VkInstance inst = VK_NULL_HANDLE;
   PFN_vkCreateInstance vkCreateInstance = (PFN_vkCreateInstance)gipa(NULL, "vkCreateInstance");
   VkApplicationInfo app = { VK_STRUCTURE_TYPE_APPLICATION_INFO, NULL, "hosttest", 1, NULL, 0, VK_API_VERSION_1_1 };
   VkInstanceCreateInfo ici = { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO, NULL, 0, &app };
   CHECK(vkCreateInstance(&ici, NULL, &inst));
   IFN(vkEnumeratePhysicalDevices); IFN(vkGetPhysicalDeviceProperties); IFN(vkEnumerateDeviceExtensionProperties);
   IFN(vkCreateDevice); IFN(vkGetDeviceProcAddr); IFN(vkGetPhysicalDeviceQueueFamilyProperties);
   uint32_t n = 1; VkPhysicalDevice pd;
   vkEnumeratePhysicalDevices(inst, &n, &pd);
   if (!n) { printf("FAIL: no GPU\n"); return 1; }
   VkPhysicalDeviceProperties props; vkGetPhysicalDeviceProperties(pd, &props);
   printf("GPU: %s, driver 0x%x\n", props.deviceName, props.driverVersion);
   uint32_t ne = 0; vkEnumerateDeviceExtensionProperties(pd, NULL, &ne, NULL);
   VkExtensionProperties *ext = calloc(ne, sizeof(*ext)); vkEnumerateDeviceExtensionProperties(pd, NULL, &ne, ext);
   int found = 0; for (uint32_t i = 0; i < ne; i++) found |= !strcmp(ext[i].extensionName, VK_EXT_EXTERNAL_MEMORY_HOST_EXTENSION_NAME);
   printf("VK_EXT_external_memory_host: %s\n", found ? "yes" : "NO");
   if (!found) { printf("RESULT: the extension is missing, this is not the new driver\n"); return 1; }

   float prio = 1; VkDeviceQueueCreateInfo qci = { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO, NULL, 0, 0, 1, &prio };
   const char *exts[] = { VK_KHR_EXTERNAL_MEMORY_EXTENSION_NAME, VK_EXT_EXTERNAL_MEMORY_HOST_EXTENSION_NAME };
   VkDeviceCreateInfo dci = { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO, NULL, 0, 1, &qci, 0, NULL, 2, exts };
   VkDevice dev; CHECK(vkCreateDevice(pd, &dci, NULL, &dev));
   DFN(vkGetMemoryHostPointerPropertiesEXT); DFN(vkAllocateMemory); DFN(vkFreeMemory); DFN(vkMapMemory);
   DFN(vkCreateBuffer); DFN(vkBindBufferMemory); DFN(vkCreateCommandPool); DFN(vkAllocateCommandBuffers);
   DFN(vkBeginCommandBuffer); DFN(vkCmdFillBuffer); DFN(vkEndCommandBuffer); DFN(vkQueueSubmit);
   DFN(vkQueueWaitIdle); DFN(vkGetDeviceQueue); DFN(vkGetBufferMemoryRequirements);

   size_t size = 16 << 20;
   uint32_t *p = mmap(NULL, size, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
   for (size_t i = 0; i < size / 4; i++) p[i] = (uint32_t)i;
   VkMemoryHostPointerPropertiesEXT hp = { VK_STRUCTURE_TYPE_MEMORY_HOST_POINTER_PROPERTIES_EXT };
   CHECK(vkGetMemoryHostPointerPropertiesEXT(dev, VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT, p, &hp));
   printf("memoryTypeBits 0x%x\n", hp.memoryTypeBits);
   if (!hp.memoryTypeBits) { printf("FAIL: no memory type\n"); return 1; }
   VkImportMemoryHostPointerInfoEXT imp = { VK_STRUCTURE_TYPE_IMPORT_MEMORY_HOST_POINTER_INFO_EXT, NULL,
      VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT, p };
   VkMemoryAllocateInfo mai = { VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO, &imp, size, (uint32_t)__builtin_ctz(hp.memoryTypeBits) };
   VkDeviceMemory mem; CHECK(vkAllocateMemory(dev, &mai, NULL, &mem));
   int ok = 1;
   for (size_t i = 0; i < size / 4; i++) if (p[i] != (uint32_t)i) { printf("FAIL: data lost at %zu\n", i); ok = 0; break; }
   void *m; CHECK(vkMapMemory(dev, mem, 0, VK_WHOLE_SIZE, 0, &m));
   printf("map %s the original pointer\n", m == p ? "is" : "is NOT");
   ok &= m == p;
   p[0] = 0x12345678;

   VkExternalMemoryBufferCreateInfo ebi = { VK_STRUCTURE_TYPE_EXTERNAL_MEMORY_BUFFER_CREATE_INFO, NULL, VK_EXTERNAL_MEMORY_HANDLE_TYPE_HOST_ALLOCATION_BIT_EXT };
   VkBufferCreateInfo bci = { VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO, &ebi, 0, size, VK_BUFFER_USAGE_TRANSFER_DST_BIT };
   VkBuffer buf; CHECK(vkCreateBuffer(dev, &bci, NULL, &buf));
   CHECK(vkBindBufferMemory(dev, buf, mem, 0));
   VkCommandPoolCreateInfo cpi = { VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO, NULL, 0, 0 };
   VkCommandPool pool; CHECK(vkCreateCommandPool(dev, &cpi, NULL, &pool));
   VkCommandBufferAllocateInfo cai = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO, NULL, pool, VK_COMMAND_BUFFER_LEVEL_PRIMARY, 1 };
   VkCommandBuffer cb; CHECK(vkAllocateCommandBuffers(dev, &cai, &cb));
   VkCommandBufferBeginInfo bi = { VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
   CHECK(vkBeginCommandBuffer(cb, &bi));
   vkCmdFillBuffer(cb, buf, 4096, 4096, 0xCAFEF00D);
   CHECK(vkEndCommandBuffer(cb));
   VkQueue q; vkGetDeviceQueue(dev, 0, 0, &q);
   VkSubmitInfo si = { VK_STRUCTURE_TYPE_SUBMIT_INFO, NULL, 0, NULL, NULL, 1, &cb };
   CHECK(vkQueueSubmit(q, 1, &si, VK_NULL_HANDLE));
   CHECK(vkQueueWaitIdle(q));
   if (p[1024] != 0xCAFEF00D || p[2047] != 0xCAFEF00D || p[2048] != 2048) { printf("FAIL: CPU doesn't see the GPU write (%x)\n", p[1024]); ok = 0; }
   else printf("GPU write seen by the CPU\n");

   vkFreeMemory(dev, mem, NULL);
   if (p[0] != 0x12345678 || p[1024] != 0xCAFEF00D || p[5000] != 5000) { printf("FAIL: data lost after free\n"); ok = 0; }
   p[10] = 7;
   printf("RESULT: %s\n", ok ? "OK, the driver works" : "FAILED");
   return !ok;
}
