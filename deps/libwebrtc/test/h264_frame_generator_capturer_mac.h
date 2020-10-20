#include "test_video_capturer.h"

#include "system_wrappers/include/clock.h"
#include "rtc_base/system/file_wrapper.h"
#include "rtc_base/platform_thread.h"
#include "common_video/h264/h264_common.h"

#include <string>
#include <memory>

namespace webrtc {
namespace test {

class H264FrameGeneratorCapturer: public TestVideoCapturer {
public:
    H264FrameGeneratorCapturer(Clock* clock, const std::string& file_path, size_t target_fps);
    ~H264FrameGeneratorCapturer();

    void Start();
    void Stop();

private:
    bool CaptureFrame();
    
    static void ProccessThread(void* obj);
    bool ProccessFile();
    bool Decode(const uint8_t * nalu, size_t size);

private:
    FileWrapper file_;
    size_t buffer_cap_;
    size_t read_index_;
    uint8_t* read_buffer_;
    std::vector<webrtc::H264::NaluIndex> offsets_;
    std::vector<webrtc::H264::NaluIndex>::iterator offset_;
    
    std::vector<webrtc::VideoFrame> frames_;

    Clock* const clock_;
    
    int requested_frame_duration_ms_;
    int max_cpu_consumption_percentage_;
    std::unique_ptr<rtc::PlatformThread> capture_thread_;
    std::atomic<bool> quit_;
};
} // namespace test
} // namespace webrtc