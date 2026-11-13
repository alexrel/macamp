// MacAmp: no recording device. The player hands AVS its own audio through avs_audio_set() (AVS_AUDIO_EXTERNAL).
#include "audio_in.h"

AVS_Audio_Input* audio_in_start(avs_audio_input_handler, void*) { return nullptr; }
void audio_in_stop(AVS_Audio_Input*) {}
std::vector<std::string> audio_in_devices() { return {}; }
bool audio_in_select_device(uint32_t) { return false; }
