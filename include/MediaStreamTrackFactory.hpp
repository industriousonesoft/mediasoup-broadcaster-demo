#ifndef MSC_TEST_MEDIA_STREAM_TRACK_FACTORY_HPP
#define MSC_TEST_MEDIA_STREAM_TRACK_FACTORY_HPP

#include "api/peer_connection_interface.h"
#include "api/media_stream_interface.h"

rtc::scoped_refptr<webrtc::PeerConnectionFactoryInterface> sharedFactory();

rtc::scoped_refptr<webrtc::AudioTrackInterface> createAudioTrack(const std::string& label);

rtc::scoped_refptr<webrtc::VideoTrackInterface> createVideoTrack(const std::string& label);

rtc::scoped_refptr<webrtc::VideoTrackInterface> createSquaresVideoTrack(const std::string& label);

#endif
