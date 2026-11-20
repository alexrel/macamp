// openmpt-render: MacAmp's module plug-in tool (in_mod). Renders a tracker module (MOD, XM, S3M, IT...) once into a
// 44.1 kHz 16-bit stereo WAV that MacAmp then plays like any file, with its EQ and visualizers.
//
//   openmpt-render <module> <output.wav>
//   openmpt-render --info <module>      length and tags only, nothing rendered: "duration=", "title=", "artist=" lines
//                                       (--info comes first: an older tool without it fails on "--info" as a file name
//                                       instead of writing over the module)
//
// stdout: "progress=<0...1>" lines while rendering; stderr: the reason when it fails (exit status 1).
// The module's title and artist go into the WAV's LIST/INFO chunk (INAM, IART), which macOS reads as tags.
// Built by scripts/build_mod_plugin.sh against libopenmpt (BSD 3-clause).
#include <libopenmpt/libopenmpt.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum { RATE = 44100, CHUNK = 4096 };
// A module that never reports its end (endless pattern jumps) stops here
static const double MAX_SECONDS = 3600;
// Modules are small; anything bigger is not one
static const long MAX_INPUT_BYTES = 64L << 20;

static void put32(unsigned char *p, uint32_t v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }
static void put16(unsigned char *p, uint16_t v) { p[0] = v; p[1] = v >> 8; }

// One INFO entry: id, size, the text with its terminating zero, padded to an even length. Returns bytes written.
static uint32_t info_entry(FILE *out, const char *id, const char *text) {
    size_t length = text ? strlen(text) : 0;
    while (length > 0 && (text[length - 1] == ' ' || text[length - 1] == '\0')) length--; // trackers pad with spaces
    if (length == 0) return 0;
    unsigned char head[8] = { id[0], id[1], id[2], id[3] };
    put32(head + 4, (uint32_t)length + 1);
    fwrite(head, 1, 8, out);
    fwrite(text, 1, length, out);
    static const unsigned char zeros[2] = { 0, 0 };
    fwrite(zeros, 1, (length + 1) % 2 ? 2 : 1, out);
    return 8 + (uint32_t)((length + 2) & ~(size_t)1);
}

static void wav_header(unsigned char h[44], uint32_t data_bytes) {
    const char *tags[] = { "RIFF", "WAVE", "fmt ", "data" };
    const int at[] = { 0, 8, 12, 36 };
    for (int i = 0; i < 4; i++) for (int j = 0; j < 4; j++) h[at[i] + j] = tags[i][j];
    put32(h + 4, 36 + data_bytes);
    put32(h + 16, 16);          // PCM fmt chunk size
    put16(h + 20, 1);           // PCM
    put16(h + 22, 2);           // stereo
    put32(h + 24, RATE);
    put32(h + 28, RATE * 4);    // bytes per second
    put16(h + 32, 4);           // bytes per frame
    put16(h + 34, 16);          // bits per sample
    put32(h + 40, data_bytes);
}

static int fail(const char *message) { fprintf(stderr, "%s\n", message); return 1; }

// The module, or NULL with the reason already on stderr
static openmpt_module *load(const char *path) {
    FILE *in = fopen(path, "rb");
    if (!in) { fail("Cannot open the module"); return NULL; }
    fseek(in, 0, SEEK_END);
    long size = ftell(in);
    fseek(in, 0, SEEK_SET);
    if (size <= 0 || size > MAX_INPUT_BYTES) { fclose(in); fail("Not a module file"); return NULL; }
    void *data = malloc(size);
    if (!data || fread(data, 1, size, in) != (size_t)size) { fclose(in); free(data); fail("Cannot read the module"); return NULL; }
    fclose(in);

    int error = 0;
    const char *message = NULL;
    openmpt_module *mod = openmpt_module_create_from_memory2(data, size, openmpt_log_func_silent, NULL, NULL, NULL,
                                                             &error, &message, NULL);
    free(data);
    if (!mod) fprintf(stderr, "Not a module libopenmpt can play%s%s\n", message ? ": " : "", message ? message : "");
    openmpt_free_string(message);
    return mod;
}

// One "key=value" line; line breaks inside a module's text become spaces
static void print_tag(const char *key, const char *value) {
    printf("%s=", key);
    size_t length = value ? strlen(value) : 0;
    while (length > 0 && value[length - 1] == ' ') length--;
    for (size_t i = 0; i < length; i++) putchar(value[i] == '\n' || value[i] == '\r' ? ' ' : value[i]);
    putchar('\n');
}

static int info(const char *path) {
    openmpt_module *mod = load(path);
    if (!mod) return 1;
    printf("duration=%.3f\n", openmpt_module_get_duration_seconds(mod));
    const char *title = openmpt_module_get_metadata(mod, "title"), *artist = openmpt_module_get_metadata(mod, "artist");
    print_tag("title", title);
    print_tag("artist", artist);
    openmpt_free_string(title);
    openmpt_free_string(artist);
    openmpt_module_destroy(mod);
    return 0;
}

int main(int argc, char **argv) {
    if (argc == 3 && strcmp(argv[1], "--info") == 0) return info(argv[2]);
    if (argc != 3) return fail("usage: openmpt-render <module> <output.wav> | --info <module>");

    openmpt_module *mod = load(argv[1]);
    if (!mod) return 1;

    FILE *out = fopen(argv[2], "wb");
    if (!out) { openmpt_module_destroy(mod); return fail("Cannot write the output file"); }
    unsigned char header[44] = { 0 };
    fwrite(header, 1, sizeof header, out);   // sizes are filled in at the end

    const double duration = openmpt_module_get_duration_seconds(mod);
    static int16_t buffer[CHUNK * 2];
    uint64_t frames = 0, last_report = 0;
    size_t count;
    while ((count = openmpt_module_read_interleaved_stereo(mod, RATE, CHUNK, buffer)) > 0) {
        // WAV is little-endian, as both Mac CPUs are
        if (fwrite(buffer, 4, count, out) != count) { fclose(out); openmpt_module_destroy(mod); return fail("Disk full"); }
        frames += count;
        if (frames - last_report >= RATE / 2 && duration > 0) {
            printf("progress=%.3f\n", (double)frames / RATE / duration > 1 ? 1.0 : (double)frames / RATE / duration);
            fflush(stdout);
            last_report = frames;
        }
        if (frames >= MAX_SECONDS * RATE) break;
    }
    // After the samples (always an even length): LIST, its size, INFO, then the entries
    const char *title = openmpt_module_get_metadata(mod, "title"), *artist = openmpt_module_get_metadata(mod, "artist");
    long list_at = ftell(out);
    unsigned char list[12] = { 'L', 'I', 'S', 'T', 0, 0, 0, 0, 'I', 'N', 'F', 'O' };
    fwrite(list, 1, sizeof list, out);
    uint32_t info_bytes = info_entry(out, "INAM", title) + info_entry(out, "IART", artist);
    openmpt_free_string(title);
    openmpt_free_string(artist);
    openmpt_module_destroy(mod);
    uint32_t list_bytes = 0;
    if (info_bytes > 0) {
        list_bytes = 12 + info_bytes;
        put32(list + 4, 4 + info_bytes);
        fseek(out, list_at, SEEK_SET);
        fwrite(list, 1, sizeof list, out);
    } else {
        fflush(out);
        ftruncate(fileno(out), list_at); // nothing to say: no empty LIST chunk
    }

    wav_header(header, (uint32_t)(frames * 4));
    put32(header + 4, 36 + (uint32_t)(frames * 4) + list_bytes);
    fseek(out, 0, SEEK_SET);
    fwrite(header, 1, sizeof header, out);
    if (fclose(out) != 0) return fail("Cannot write the output file");
    if (frames == 0) return fail("The module is silent");
    printf("progress=1.000\n");
    return 0;
}
