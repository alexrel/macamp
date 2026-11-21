// gme-render: MacAmp's chiptune plug-in tool (in_gme). Renders one song of a game music file (NSF, SPC, GBS, VGM...)
// once into a 44.1 kHz 16-bit stereo WAV that MacAmp then plays like any file, with its EQ and visualizers.
//
//   gme-render [--track N] <file> <output.wav>
//   gme-render --info [--track N] <file>   length and tags only, nothing rendered: "duration=", "title=", "artist=",
//                                          "tracks=" lines (--info comes first, as in openmpt-render)
//
// N counts from 1 (the file's first song when left out). NSF, GBS, HES, KSS, AY and SAP hold a whole soundtrack:
// MacAmp lists each song as file#track=N. A song without a length in the file plays 2:30 and fades out, as in
// Game_Music_Emu's own player, or less: the song ends after a few seconds of silence (an NSF knows no lengths, so --info
// plays such a song through without writing it, ~10 ms, to tell its real length). A "<file>.m3u" next to it (the usual NSF / GBS packs) gives the songs names and lengths.
// stdout: "progress=<0...1>" lines while rendering; stderr: the reason when it fails (exit status 1).
// Built by scripts/build_chiptune_plugin.sh against libgme (LGPL 2.1).
#include <gme/gme.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

enum { RATE = 44100, CHUNK = 4096 };
// A song that never ends stops here
static const int MAX_SECONDS = 3600;
// Fade when the file names none (Game_Music_Emu's player uses the same)
static const int DEFAULT_FADE_MS = 8000;

static void put32(unsigned char *p, uint32_t v) { p[0] = v; p[1] = v >> 8; p[2] = v >> 16; p[3] = v >> 24; }
static void put16(unsigned char *p, uint16_t v) { p[0] = v; p[1] = v >> 8; }

// One INFO entry: id, size, the text with its terminating zero, padded to an even length. Returns bytes written.
static uint32_t info_entry(FILE *out, const char *id, const char *text) {
    size_t length = text ? strlen(text) : 0;
    while (length > 0 && text[length - 1] == ' ') length--;
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

// The file opened at RATE, its "<file>.m3u" applied; NULL with the reason on stderr
static Music_Emu *open_file(const char *path) {
    Music_Emu *emu = NULL;
    gme_err_t error = gme_open_file(path, &emu, RATE);
    if (error) { fprintf(stderr, "Not a file Game_Music_Emu can play: %s\n", error); return NULL; }
    char m3u[4096];
    const char *dot = strrchr(path, '.');
    if (dot && snprintf(m3u, sizeof m3u, "%.*s.m3u", (int)(dot - path), path) < (int)sizeof m3u && access(m3u, R_OK) == 0)
        gme_load_m3u(emu, m3u); // a broken playlist leaves the file's own songs
    return emu;
}

// Length to render: the song's own, or 2:30, plus its fade
static int length_ms(const gme_info_t *info, int *fade) {
    *fade = info->fade_length > 0 ? info->fade_length : DEFAULT_FADE_MS;
    return info->play_length > 0 ? info->play_length : 150000;
}

// The title the playlist shows: the song's name, else the game's, numbered when the file holds several songs
static void title(const gme_info_t *info, int track, int count, char *out, size_t size) {
    if (info->song && *info->song) snprintf(out, size, "%s", info->song);
    else if (count > 1) snprintf(out, size, "%s%s#%d", info->game ? info->game : "", info->game && *info->game ? " " : "", track + 1);
    else snprintf(out, size, "%s", info->game ? info->game : "");
}

// One "key=value" line; line breaks inside a file's text become spaces
static void print_tag(const char *key, const char *value) {
    printf("%s=", key);
    for (const char *c = value ? value : ""; *c; c++) putchar(*c == '\n' || *c == '\r' ? ' ' : *c);
    putchar('\n');
}

// Plays the started song to its end (the fade, or silence), into `out` when given; frames played, or -1 with the
// reason on stderr. Progress lines only while writing.
static int64_t play(Music_Emu *emu, double duration, FILE *out) {
    static short buffer[CHUNK * 2];
    uint64_t frames = 0, last_report = 0;
    while (!gme_track_ended(emu) && frames < (uint64_t)MAX_SECONDS * RATE) {
        gme_err_t error = gme_play(emu, CHUNK * 2, buffer);
        if (error) { fail(error); return -1; }
        // WAV is little-endian, as both Mac CPUs are
        if (out && fwrite(buffer, 4, CHUNK, out) != CHUNK) { fail("Disk full"); return -1; }
        frames += CHUNK;
        if (out && frames - last_report >= RATE / 2) {
            double done = (double)frames / RATE / duration;
            printf("progress=%.3f\n", done > 1 ? 1.0 : done);
            fflush(stdout);
            last_report = frames;
        }
    }
    return (int64_t)frames;
}

// Opens the file at RATE and starts the song with its fade; NULL with the reason on stderr
static Music_Emu *start(const char *path, int track, gme_info_t **info, int *count, double *duration) {
    Music_Emu *emu = open_file(path);
    if (!emu) return NULL;
    *count = gme_track_count(emu);
    if (track >= *count || gme_track_info(emu, info, track)) { gme_delete(emu); fail("No such song in the file"); return NULL; }
    gme_err_t error = gme_start_track(emu, track);
    if (error) { gme_free_info(*info); gme_delete(emu); fail(error); return NULL; }
    int fade, length = length_ms(*info, &fade);
    gme_set_fade_msecs(emu, length, fade);
    *duration = (length + fade) / 1000.0;
    return emu;
}

static int info(const char *path, int track) {
    gme_info_t *info = NULL;
    int count;
    double duration;
    Music_Emu *emu = start(path, track, &info, &count, &duration);
    if (!emu) return 1;
    if (info->length <= 0 && info->loop_length <= 0) { // no length in the file: what rendering will give
        int64_t frames = play(emu, duration, NULL);
        if (frames > 0) duration = (double)frames / RATE;
    }
    char name[512];
    title(info, track, count, name, sizeof name);
    printf("duration=%.3f\n", duration);
    print_tag("title", name);
    print_tag("artist", info->author);
    printf("tracks=%d\n", count);
    gme_free_info(info);
    gme_delete(emu);
    return 0;
}

int main(int argc, char **argv) {
    int at = 1, info_only = 0, track = 0;
    if (at < argc && strcmp(argv[at], "--info") == 0) { info_only = 1; at++; }
    if (at + 1 < argc && strcmp(argv[at], "--track") == 0) { track = atoi(argv[at + 1]) - 1; at += 2; }
    if (track < 0 || argc - at != (info_only ? 1 : 2))
        return fail("usage: gme-render [--track N] <file> <output.wav> | --info [--track N] <file>");
    if (info_only) return info(argv[at], track);

    gme_info_t *info = NULL;
    int count;
    double duration;
    Music_Emu *emu = start(argv[at], track, &info, &count, &duration);
    if (!emu) return 1;

    FILE *out = fopen(argv[at + 1], "wb");
    if (!out) { gme_free_info(info); gme_delete(emu); return fail("Cannot write the output file"); }
    unsigned char header[44] = { 0 };
    fwrite(header, 1, sizeof header, out);   // sizes are filled in at the end

    int64_t played = play(emu, duration, out);
    if (played < 0) { fclose(out); gme_free_info(info); gme_delete(emu); return 1; }
    uint64_t frames = (uint64_t)played;
    // After the samples (always an even length): LIST, its size, INFO, then the entries
    char name[512];
    title(info, track, count, name, sizeof name);
    long list_at = ftell(out);
    unsigned char list[12] = { 'L', 'I', 'S', 'T', 0, 0, 0, 0, 'I', 'N', 'F', 'O' };
    fwrite(list, 1, sizeof list, out);
    uint32_t info_bytes = info_entry(out, "INAM", name) + info_entry(out, "IART", info->author);
    gme_free_info(info);
    gme_delete(emu);
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
    if (frames == 0) return fail("The song is silent");
    printf("progress=1.000\n");
    return 0;
}
