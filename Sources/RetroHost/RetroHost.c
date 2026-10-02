#include "RetroHost.h"
#include "libretro.h"
#include <dlfcn.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdarg.h>
#include <stdatomic.h>
static void *handle;
static void (*r_init)(void),(*r_deinit)(void),(*r_run)(void),(*r_reset)(void),(*r_unload)(void);
static bool (*r_load)(const struct retro_game_info*),(*r_serialize)(void*,size_t),(*r_unserialize)(const void*,size_t);
static size_t (*r_size)(void),(*r_memsize)(unsigned);
static void *(*r_memdata)(unsigned);
static struct retro_system_info info;
static struct retro_system_av_info av;
static char error[1024],systemdir[4096],savedir[4096],corepath[4096];
static void *rom;
static uint32_t *pixels;
static unsigned width,height,format;
static uint64_t frames;
static int16_t analogs[4][2][2];
static int16_t buttons[4][16],pointer_x,pointer_y,pointer_pressed;
static float audio_ring[262144];
static atomic_uint audio_read,audio_write;
static struct {char key[128],value[256];} options[256];
static unsigned noptions;
static struct {char key[128],definition[16384];} option_catalog[512];
static unsigned catalog_count;
static bool catalog_mode;
static void catalog_option(const char *key,const char *definition) {
 if(!catalog_mode||!key||!definition||catalog_count>=512)return;
 snprintf(option_catalog[catalog_count].key,128,"%s",key);
 snprintf(option_catalog[catalog_count++].definition,16384,"%s",definition);
}
static bool loaded,shutdown_requested;
static void log_cb(enum retro_log_level level,const char *fmt,...) { if(level<RETRO_LOG_INFO)return; va_list a; va_start(a,fmt); vfprintf(stderr,fmt,a); va_end(a); }
static bool environment(unsigned cmd,void *data) {
 switch(cmd) {
 case RETRO_ENVIRONMENT_GET_SYSTEM_DIRECTORY: *(const char**)data=systemdir; return true;
 case RETRO_ENVIRONMENT_GET_SAVE_DIRECTORY: *(const char**)data=savedir; return true;
 case RETRO_ENVIRONMENT_GET_LIBRETRO_PATH: *(const char**)data=corepath; return true;
 case RETRO_ENVIRONMENT_SET_PIXEL_FORMAT: format=*(unsigned*)data; return format<=2;
 case RETRO_ENVIRONMENT_GET_CAN_DUPE: *(bool*)data=true; return true;
 case RETRO_ENVIRONMENT_GET_LOG_INTERFACE: ((struct retro_log_callback*)data)->log=log_cb; return true;
 case RETRO_ENVIRONMENT_GET_VARIABLE: {struct retro_variable *v=data;v->value=NULL;for(unsigned i=0;i<noptions;i++)if(!strcmp(v->key,options[i].key)){v->value=options[i].value;return true;}return false;}
 case RETRO_ENVIRONMENT_GET_VARIABLE_UPDATE: *(bool*)data=false; return true;
 case RETRO_ENVIRONMENT_GET_CORE_OPTIONS_VERSION: *(unsigned*)data=0; return true;
 case RETRO_ENVIRONMENT_SET_VARIABLES: {const struct retro_variable *v=data;for(;v->key;v++){catalog_option(v->key,v->value);bool found=false;for(unsigned i=0;i<noptions;i++)if(!strcmp(v->key,options[i].key))found=true;if(found||noptions>=256)continue;const char *s=strchr(v->value,';');if(!s)continue;s++;while(*s==' ')s++;snprintf(options[noptions].key,128,"%s",v->key);size_t n=strcspn(s,"|");snprintf(options[noptions].value,256,"%.*s",(int)n,s);noptions++;}return true;}
 case RETRO_ENVIRONMENT_SET_SUPPORT_NO_GAME: case RETRO_ENVIRONMENT_SET_INPUT_DESCRIPTORS: case RETRO_ENVIRONMENT_SET_CONTROLLER_INFO: return true;
 case RETRO_ENVIRONMENT_SET_SYSTEM_AV_INFO: av=*(struct retro_system_av_info*)data;return true;
 case RETRO_ENVIRONMENT_SET_GEOMETRY: av.geometry=*(struct retro_game_geometry*)data;return true;
 case RETRO_ENVIRONMENT_GET_LANGUAGE: *(unsigned*)data=RETRO_LANGUAGE_ENGLISH;return true;
 case RETRO_ENVIRONMENT_GET_INPUT_BITMASKS:return true;
 case RETRO_ENVIRONMENT_SHUTDOWN:shutdown_requested=true;return true;
 default:return false;
 }
}
static void video(const void *data,unsigned w,unsigned h,size_t pitch) {
 if(!data||data==RETRO_HW_FRAME_BUFFER_VALID||w>4096||h>4096)return;
 if(w!=width||h!=height){uint32_t *p=realloc(pixels,(size_t)w*h*4);if(!p)return;pixels=p;width=w;height=h;}
 for(unsigned y=0;y<h;y++)for(unsigned x=0;x<w;x++){
 unsigned r,g,b;const uint8_t *row=(const uint8_t*)data+y*pitch;
 if(format==RETRO_PIXEL_FORMAT_XRGB8888){uint32_t p=((const uint32_t*)row)[x];r=(p>>16)&255;g=(p>>8)&255;b=p&255;}
 else {uint16_t p=((const uint16_t*)row)[x];if(format==RETRO_PIXEL_FORMAT_RGB565){r=((p>>11)&31)*255/31;g=((p>>5)&63)*255/63;b=(p&31)*255/31;}else{r=((p>>10)&31)*255/31;g=((p>>5)&31)*255/31;b=(p&31)*255/31;}}
 pixels[(size_t)y*w+x]=0xff000000|(r<<16)|(g<<8)|b;
 }frames++;
}
static size_t audio_batch(const int16_t *data,size_t n){unsigned wr=atomic_load(&audio_write),rd=atomic_load(&audio_read);for(size_t i=0;i<n;i++){if(wr-rd>=131071)break;audio_ring[(wr*2)&262143]=data[i*2]/32768.f;audio_ring[(wr*2+1)&262143]=data[i*2+1]/32768.f;wr++;}atomic_store(&audio_write,wr);return n;}
static void audio_sample(int16_t l,int16_t r){int16_t a[2]={l,r};audio_batch(a,1);}
static void poll(void){}
static int16_t input(unsigned p,unsigned device,unsigned index,unsigned id){if((device&255)==RETRO_DEVICE_ANALOG)return p<4&&index<2&&id<2?analogs[p][index][id]:0;if(device==RETRO_DEVICE_POINTER){if(id==RETRO_DEVICE_ID_POINTER_X)return pointer_x;if(id==RETRO_DEVICE_ID_POINTER_Y)return pointer_y;if(id==RETRO_DEVICE_ID_POINTER_PRESSED)return pointer_pressed;return 0;}if(p>=4||(device&255)!=RETRO_DEVICE_JOYPAD)return 0;if(id==RETRO_DEVICE_ID_JOYPAD_MASK){unsigned mask=0;for(int i=0;i<16;i++)if(buttons[p][i])mask|=1<<i;return (int16_t)mask;}return id<16?buttons[p][id]:0;}
#define SYM(var,name) do{*(void**)(&var)=dlsym(handle,name);if(!var){snprintf(error,sizeof(error),"Missing ABI symbol: %s",name);goto fail;}}while(0)
int arm_load(const char *core,const char *game,const char *system,const char *saves,const char *opts){
 arm_stop();error[0]=0;format=0;frames=0;shutdown_requested=false;noptions=0;memset(buttons,0,sizeof(buttons));memset(analogs,0,sizeof(analogs));atomic_store(&audio_read,0);atomic_store(&audio_write,0);
 snprintf(systemdir,sizeof(systemdir),"%s",system);snprintf(savedir,sizeof(savedir),"%s",saves);snprintf(corepath,sizeof(corepath),"%s",core);
 if(opts){char *copy=strdup(opts),*line=strtok(copy,"\n");while(line&&noptions<256){char *eq=strchr(line,'=');if(eq){*eq=0;snprintf(options[noptions].key,128,"%s",line);snprintf(options[noptions++].value,256,"%s",eq+1);}line=strtok(NULL,"\n");}free(copy);}
 handle=dlopen(core,RTLD_NOW|RTLD_LOCAL);if(!handle){snprintf(error,sizeof(error),"%s",dlerror());return 0;}
 void (*setenv)(retro_environment_t),(*setvideo)(retro_video_refresh_t),(*setaudio)(retro_audio_sample_t),(*setbatch)(retro_audio_sample_batch_t),(*setpoll)(retro_input_poll_t),(*setinput)(retro_input_state_t),(*getinfo)(struct retro_system_info*),(*getav)(struct retro_system_av_info*),(*setcontroller)(unsigned,unsigned);unsigned (*version)(void);
 SYM(version,"retro_api_version");if(version()!=RETRO_API_VERSION){snprintf(error,sizeof(error),"Unsupported libretro ABI");goto fail;}
 SYM(r_init,"retro_init");SYM(r_deinit,"retro_deinit");SYM(r_run,"retro_run");SYM(r_reset,"retro_reset");SYM(r_load,"retro_load_game");SYM(r_unload,"retro_unload_game");SYM(r_size,"retro_serialize_size");SYM(r_serialize,"retro_serialize");SYM(r_unserialize,"retro_unserialize");SYM(r_memsize,"retro_get_memory_size");SYM(r_memdata,"retro_get_memory_data");
 SYM(setenv,"retro_set_environment");SYM(setvideo,"retro_set_video_refresh");SYM(setaudio,"retro_set_audio_sample");SYM(setbatch,"retro_set_audio_sample_batch");SYM(setpoll,"retro_set_input_poll");SYM(setinput,"retro_set_input_state");SYM(getinfo,"retro_get_system_info");SYM(getav,"retro_get_system_av_info");SYM(setcontroller,"retro_set_controller_port_device");
 setenv(environment);setvideo(video);setaudio(audio_sample);setbatch(audio_batch);setpoll(poll);setinput(input);getinfo(&info);r_init();
 struct retro_game_info gi={0};gi.path=game;
 if(!info.need_fullpath){FILE *f=fopen(game,"rb");if(!f){snprintf(error,sizeof(error),"Cannot read game");r_deinit();goto fail;}fseek(f,0,SEEK_END);long sz=ftell(f);rewind(f);if(sz<=0||sz>1024L*1024*1024){fclose(f);snprintf(error,sizeof(error),"Invalid or oversized ROM");r_deinit();goto fail;}rom=malloc(sz);if(!rom||fread(rom,1,sz,f)!=(size_t)sz){fclose(f);snprintf(error,sizeof(error),"ROM read failed");r_deinit();goto fail;}fclose(f);gi.data=rom;gi.size=sz;}
 if(!r_load(&gi)){snprintf(error,sizeof(error),"%s rejected this game; check firmware and runtime log",info.library_name);r_deinit();goto fail;}loaded=true;getav(&av);for(unsigned p=0;p<4;p++)setcontroller(p,RETRO_DEVICE_JOYPAD);return 1;
 fail:free(rom);rom=NULL;if(handle)dlclose(handle);handle=NULL;return 0;
}
void arm_run(void){if(loaded&&!shutdown_requested)r_run();}
void arm_reset(void){if(loaded)r_reset();}
void arm_stop(void){if(loaded){r_unload();r_deinit();}loaded=false;if(handle)dlclose(handle);handle=NULL;free(rom);rom=NULL;free(pixels);pixels=NULL;width=height=0;}
const char *arm_error(void){return error;}const char *arm_core_name(void){return loaded?info.library_name:"";}
double arm_aspect_ratio(void){return av.geometry.aspect_ratio>0?av.geometry.aspect_ratio:(height?(double)width/height:1);}
double arm_fps(void){return av.timing.fps>1?av.timing.fps:60;}double arm_sample_rate(void){return av.timing.sample_rate>1?av.timing.sample_rate:48000;}
const uint32_t *arm_pixels(void){return pixels;}unsigned arm_width(void){return width;}unsigned arm_height(void){return height;}uint64_t arm_frames(void){return frames;}
void arm_analog(unsigned p,unsigned stick,unsigned axis,int16_t value){if(p<4&&stick<2&&axis<2)analogs[p][stick][axis]=value;}
void arm_pointer(int16_t x,int16_t y,int pressed){pointer_x=x;pointer_y=y;pointer_pressed=pressed;}
void arm_input(unsigned p,unsigned id,int16_t v){if(p<4&&id<16)buttons[p][id]=v;}
size_t arm_audio(float *out,size_t n){unsigned rd=atomic_load(&audio_read),wr=atomic_load(&audio_write);size_t count=0;for(size_t i=0;i<n;i++){if(rd!=wr){out[i*2]=audio_ring[(rd*2)&262143];out[i*2+1]=audio_ring[(rd*2+1)&262143];rd++;count++;}else out[i*2]=out[i*2+1]=0;}atomic_store(&audio_read,rd);return count;}
static int transfer(const char *path,void *data,size_t size,int save){if(!size||!data)return 0;FILE *f=fopen(path,save?"wb":"rb");if(!f)return 0;size_t n=save?fwrite(data,1,size,f):fread(data,1,size,f);int result=fclose(f);return n==size&&result==0;}
int arm_sram(const char *path,int save){if(!loaded)return 0;return transfer(path,r_memdata(RETRO_MEMORY_SAVE_RAM),r_memsize(RETRO_MEMORY_SAVE_RAM),save);}
int arm_state(const char *path,int save){if(!loaded)return 0;size_t sz=r_size();if(!sz)return 0;void *p=malloc(sz);if(!p)return 0;int ok=save?(r_serialize(p,sz)&&transfer(path,p,sz,1)):(transfer(path,p,sz,0)&&r_unserialize(p,sz));free(p);return ok;}

int arm_inspect(const char *core) {
 void *h=dlopen(core,RTLD_NOW|RTLD_LOCAL);if(!h){snprintf(error,sizeof(error),"%s",dlerror());return 0;}
 unsigned (*version)(void)=dlsym(h,"retro_api_version");
 const char *required[]={"retro_init","retro_deinit","retro_load_game","retro_unload_game","retro_run","retro_get_system_info","retro_get_system_av_info","retro_set_environment","retro_set_video_refresh","retro_set_input_state","retro_set_input_poll","retro_serialize","retro_unserialize"};
 int ok=version && version()==RETRO_API_VERSION;
 for(unsigned i=0;i<sizeof(required)/sizeof(required[0]);i++)if(!dlsym(h,required[i]))ok=0;
 dlclose(h);if(!ok)snprintf(error,sizeof(error),"Incomplete libretro ABI");return ok;
}

// Runs in a short-lived helper process. Does not initialize a core or load a ROM.
int arm_query_options(const char *core) {
 catalog_count=0;noptions=0;catalog_mode=true;
 void *h=dlopen(core,RTLD_NOW|RTLD_LOCAL);
 if(!h){snprintf(error,sizeof(error),"%s",dlerror());catalog_mode=false;return 0;}
 void (*setenv)(retro_environment_t)=dlsym(h,"retro_set_environment");
 if(setenv)setenv(environment);
 dlclose(h);catalog_mode=false;
 if(!setenv){snprintf(error,sizeof(error),"Missing option registration ABI");return 0;}
 return 1;
}
unsigned arm_option_count(void){return catalog_count;}
const char *arm_option_key(unsigned i){return i<catalog_count?option_catalog[i].key:"";}
const char *arm_option_definition(unsigned i){return i<catalog_count?option_catalog[i].definition:"";}
