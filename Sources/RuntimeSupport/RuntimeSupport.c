#include "RuntimeSupport.h"
#include <zlib.h>
size_t akito_zlib_bound(size_t count) { return (size_t)compressBound((uLong)count); }
int akito_zlib_compress(const unsigned char *input, size_t count, unsigned char *output, size_t *output_count) {
 uLongf length=(uLongf)*output_count;
 int result=compress2(output,&length,input,(uLong)count,Z_BEST_COMPRESSION);
 *output_count=(size_t)length;
 return result;
}

#include <unistd.h>
#include <string.h>
#include <errno.h>
#include <limits.h>
/* Fixed-buffer extraction: never write beyond the verified per-entry budget. */
int akito_zip_extract(const unsigned char *input, size_t count, int method, int fd, unsigned long long expected, unsigned long checksum) {
 unsigned char output[65536]; unsigned long long total=0; uLong crc=crc32(0L,Z_NULL,0);
 z_stream stream={0}; int result=Z_OK;
 if(method!=0 && method!=8) return -1;
 if(method==8 && inflateInit2(&stream,-MAX_WBITS)!=Z_OK) return -1;
 size_t position=0;
 do {
  size_t length=0;
  if(method==0) { length=count-position; if(length>sizeof(output))length=sizeof(output); if(length)memcpy(output,input+position,length); position+=length; result=position==count?Z_STREAM_END:Z_OK; }
  else {
   if(!stream.avail_in && position<count) {size_t chunk=count-position;if(chunk>UINT_MAX)chunk=UINT_MAX;stream.next_in=(Bytef*)input+position;stream.avail_in=(uInt)chunk;position+=chunk;}
   stream.next_out=output;stream.avail_out=sizeof(output);result=inflate(&stream,Z_NO_FLUSH);length=sizeof(output)-stream.avail_out;
   if(result!=Z_OK && result!=Z_STREAM_END)break;
   if(!length && !stream.avail_in && position==count && result!=Z_STREAM_END){result=Z_DATA_ERROR;break;}
  }
  if(length>expected-total){result=Z_DATA_ERROR;break;}
  size_t written=0;
  while(written<length){ssize_t n=write(fd,output+written,length-written);if(n<0 && errno==EINTR)continue;if(n<=0){result=Z_ERRNO;break;}written+=(size_t)n;}
  if(result==Z_ERRNO)break;
  total+=length;crc=crc32(crc,output,(uInt)length);
 }while(result!=Z_STREAM_END);
 int valid=result==Z_STREAM_END && total==expected && crc==checksum && position==count && (method==0 || stream.avail_in==0);
 if(method==8)inflateEnd(&stream);
 return valid?0:-1;
}
