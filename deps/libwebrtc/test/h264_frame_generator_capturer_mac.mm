#include "h264_frame_generator_capturer_mac.h"

#include "api/video/i420_buffer.h"
#include "rtc_base/checks.h"
#include "rtc_base/logging.h"
#include "rtc_base/time_utils.h"
#include "system_wrappers/include/sleep.h"
#include "sdk/objc/components/video_codec/nalu_rewriter.h"
#include "api/video/video_frame.h"
#include "sdk/objc/base/RTCEncodedImage.h"
#include "sdk/objc/base/RTCI420Buffer.h"
#include "sdk/objc/base/RTCYUVPlanarBuffer.h"
#include "sdk/objc/base/RTCVideoFrameBuffer.h"
#include "sdk/objc/base/RTCVideoDecoder.h"
#include "sdk/objc/components/video_codec/RTCVideoDecoderH264.h"

namespace webrtc {
namespace test {

static id<RTCVideoDecoder> video_decoder_;

const static long default_buffer_cap = 1280 * 720;
    
H264FrameGeneratorCapturer::H264FrameGeneratorCapturer(Clock* clock, const std::string& file_path, size_t target_fps) :
    clock_(clock),
    file_(FileWrapper::OpenReadOnly(file_path)),
    buffer_cap_(default_buffer_cap),
    read_index_(0),
    read_buffer_(nullptr),
    requested_frame_duration_ms_((int)(1000.0f / target_fps)),
    max_cpu_consumption_percentage_(50),
    quit_(false)
{
    RTC_CHECK(file_.is_open());
    RTC_CHECK(buffer_cap_ > 0);
    
    read_buffer_ = static_cast<uint8_t *>(malloc(buffer_cap_));

    if(capture_thread_ == nullptr) {
        capture_thread_.reset(new rtc::PlatformThread(H264FrameGeneratorCapturer::ProccessThread, this, "H264FrameGeneratorCapturer", rtc::kHighPriority));
    }

    frames_ = std::vector<webrtc::VideoFrame>();
    video_decoder_ = [[RTCVideoDecoderH264 alloc] init];
    [video_decoder_ setCallback:^(RTCVideoFrame* _Nonnull frame) {
        
        @autoreleasepool {
    
            // RTC_LOG(LS_INFO) << "Did decoded..." << frame.width << "x"<< frame.height;
            id<RTCYUVPlanarBuffer> i420Buffer = frame.buffer.toI420;
            
            rtc::scoped_refptr<webrtc::I420Buffer> dst_buffer(webrtc::I420Buffer::Copy(frame.width, frame.height, i420Buffer.dataY, i420Buffer.strideY, i420Buffer.dataU, i420Buffer.strideU, i420Buffer.dataV, i420Buffer.strideV));
           
            // webrtc::VideoFrame captureFrame = webrtc::VideoFrame::Builder()
            //                                        .set_video_frame_buffer(dst_buffer)
            //                                        .set_timestamp_rtp(0)
            //                                        .set_timestamp_ms(rtc::TimeMillis())
            //                                        .set_rotation(webrtc::kVideoRotation_0)
            //                                        .build();
            VideoFrame::UpdateRect rect = VideoFrame::UpdateRect();
            rect.offset_x = 0;
            rect.offset_y = 0;
            rect.width = 1280;
            rect.height = 720;
             VideoFrame captureFrame = VideoFrame::Builder()
                           .set_video_frame_buffer(dst_buffer)
                           .set_rotation(webrtc::kVideoRotation_0)
                           .set_update_rect(rect)
                           .set_timestamp_us(clock_->TimeInMicroseconds())
                           .set_ntp_time_ms(clock_->CurrentNtpInMilliseconds())
                           .build();
             TestVideoCapturer::OnFrame(captureFrame);
            
             i420Buffer = nil;
            
        }
        
    }];
}

H264FrameGeneratorCapturer::~H264FrameGeneratorCapturer() {
    file_.Close();
    if (read_buffer_ != nullptr) {
        free(read_buffer_);
        read_buffer_ = nullptr;
    }
    if (capture_thread_) {
      quit_ = true;
      capture_thread_->Stop();
      capture_thread_.reset();
    }
    
    [video_decoder_ releaseDecoder];
    video_decoder_ = NULL;
}

void H264FrameGeneratorCapturer::Start() {
    if (capture_thread_) {
        capture_thread_->Start();
    }
}

void H264FrameGeneratorCapturer::Stop() {
    if (capture_thread_) {
        capture_thread_->Stop();
    }
}

bool H264FrameGeneratorCapturer::ProccessFile() {
    
    if (offsets_.size() == 0 && file_.ReadEof()) {
        NSLog(@"no more file packets...");
        return false;
    }
    
    if (offsets_.size() == 0 && file_.ReadEof() == false) {
        memset(read_buffer_, 0, buffer_cap_);
        file_.SeekTo(read_index_);
        size_t read_size = file_.Read((char *)(read_buffer_), buffer_cap_);
        
        if(read_size > 0) {
            offsets_ = webrtc::H264::FindNaluIndices(read_buffer_, read_size);
            //如果文件未读完，那么解析列表的最后一个nalu可能是不完整的，因为解析完整的nalu需要参考下一个nalu的start code，所以不将其包括在解码列表中
            if(file_.ReadEof() == false) {
                offsets_.pop_back();
            }
        
            offset_ = offsets_.begin();
        
            NaluIndex first_nalu = offsets_.front();
            NaluIndex last_nalu = offsets_.back();
        
            size_t nalu_size_sum = last_nalu.payload_start_offset + last_nalu.payload_size - first_nalu.payload_start_offset + 0x04/*第一个nalu的start code*/;
            read_index_ += nalu_size_sum;
            NSLog(@"nalu_size_sum: %ld", nalu_size_sum);
        }

    }
    
    if (offset_ != offsets_.end()) {
        //non-VCL: sps&pps (这两个nalu似乎总是同时出现的)
        if (webrtc::H264::ParseNaluType(*(read_buffer_ + offset_->payload_start_offset)) == webrtc::H264::kSps) {
            size_t sps_offset = offset_->payload_start_offset;
            size_t sps_size = offset_->payload_size;
            //PPS
            ++offset_;
            size_t pps_size = offset_->payload_size;
           
            const uint8_t* sps_pps_buffer = read_buffer_ + sps_offset - 0x04;
            size_t sps_pps_size = sps_size + pps_size + 0x04 + 0x04;
            
            Decode(sps_pps_buffer, sps_pps_size);
           
            NSLog(@"sps - pps");

        //VCL
        }else {
            const uint8_t* nalu_buffer = read_buffer_+offset_->payload_start_offset-0x04;
            size_t nalu_size = offset_->payload_size + 0x04;
            
            Decode(nalu_buffer, nalu_size);
        }
        
        ++offset_;
        if (offset_ == offsets_.end()) {
            offsets_.clear();
        }
    }
    
    return true;
}

bool H264FrameGeneratorCapturer::Decode(const uint8_t *nalu, size_t size) {
    @autoreleasepool {
        RTCEncodedImage* encodedFrame = [[RTCEncodedImage alloc] init];
          NSData* data = [[NSData alloc] initWithBytes:nalu length:size];
          encodedFrame.buffer = data;
        //   NSLog(@"%@", encodedFrame.buffer);
          encodedFrame.encodedWidth = 1280;
          encodedFrame.encodedHeight = 720;
          encodedFrame.completeFrame = YES;
          encodedFrame.frameType = RTCFrameTypeVideoFrameDelta; //解码前会根据NALU结构可知，此处暂时设为普通frame
          encodedFrame.captureTimeMs = rtc::TimeMillis();
          encodedFrame.timeStamp = 0;
          encodedFrame.rotation = RTCVideoRotation_0;
        
          NSInteger ret = [video_decoder_ decode:encodedFrame missingFrames:NO codecSpecificInfo:nil renderTimeMs:0];
          if (ret == WEBRTC_VIDEO_CODEC_ERROR) {
              NSLog(@"Failed to decode frame..");
              return false;
          }
          return true;
    }
}

//MARK: - Proccess Thread
void H264FrameGeneratorCapturer::ProccessThread(void *obj) {
    auto self = static_cast<H264FrameGeneratorCapturer *>(obj);
    while (self->CaptureFrame()) {}
}

bool H264FrameGeneratorCapturer::CaptureFrame() {
    if (quit_) {
        return false;
    }
    
    int64_t started_time = rtc::TimeMillis();
      //视频采集
    if (ProccessFile()) {
        int last_capture_duration = (int)(rtc::TimeMillis() - started_time);
          //以上一次采样时长作为参考，估算采样周期 = 上一次采样时长 / 采样CPU占比（范围0.0~1.0）
        int capture_period =
            std::max((last_capture_duration * 100) / max_cpu_consumption_percentage_,
                     requested_frame_duration_ms_);
          //使用采样周期计算下一次采样时差
        int delta_time = capture_period - last_capture_duration;
          //存在时差说明下一次采样需要等待，否则马上执行下一次采样
        if (delta_time > 0) {
            // NSLog(@"sleep ms: %d - %d - %d", delta_time, capture_period, last_capture_duration);
            webrtc::SleepMs(delta_time);
        }
        return true;
    }else {
        return false;
    }
    
}


}
}

