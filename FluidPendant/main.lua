local prev = rawget(_G, "FLUID_PENDANT_APP")
if prev and prev.stop then
  pcall(function()
    prev.stop("reload")
  end)
end

FLUID_PENDANT_APP = {
  VERSION = "2026-05-01-fluid-viper-batch-edge-v1"
}

local APP = FLUID_PENDANT_APP

local pcall_fn = pcall
local math_floor = math.floor
local math_sqrt = math.sqrt
local math_sin = math.sin
local math_cos = math.cos
local math_rad = math.rad
local math_abs = math.abs
local string_format = string.format

local lv_canvas_create_fn = rawget(_G, "lv_canvas_create")
local lv_canvas_frame_begin_fn = rawget(_G, "lv_canvas_frame_begin") or rawget(_G, "lv_canvas_begin")
local lv_canvas_frame_end_fn = rawget(_G, "lv_canvas_frame_end") or rawget(_G, "lv_canvas_end")
local lv_canvas_fill_bg_fn = rawget(_G, "lv_canvas_fill_bg") or rawget(_G, "lv_canvas_fill")
local lv_canvas_draw_rect_fn = rawget(_G, "lv_canvas_draw_rect")
local lv_label_create_fn = rawget(_G, "lv_label_create")
local lv_label_set_text_fn = rawget(_G, "lv_label_set_text")
local lv_obj_set_pos_fn = rawget(_G, "lv_obj_set_pos")
local lv_obj_align_fn = rawget(_G, "lv_obj_align")
local lv_obj_set_style_bg_color_fn = rawget(_G, "lv_obj_set_style_bg_color")
local lv_obj_set_style_bg_opa_fn = rawget(_G, "lv_obj_set_style_bg_opa")
local lv_obj_set_style_text_color_fn = rawget(_G, "lv_obj_set_style_text_color")
local lv_obj_set_style_text_opa_fn = rawget(_G, "lv_obj_set_style_text_opa")
local lv_obj_set_style_text_font_fn = rawget(_G, "lv_obj_set_style_text_font")
local lv_obj_clear_flag_fn = rawget(_G, "lv_obj_clear_flag")
local lv_obj_invalidate_fn = rawget(_G, "lv_obj_invalidate")
local runtime_app = rawget(_G, "app")
local app_exiting_fn = runtime_app and runtime_app.exiting or nil
local app_on_fn = runtime_app and runtime_app.on or nil
local runtime_tmr = rawget(_G, "tmr")
local tmr_now_fn = runtime_tmr and runtime_tmr.now or nil
local millis_fn = rawget(_G, "millis")
local runtime_time = rawget(_G, "time")
local time_getlocal_fn = runtime_time and runtime_time.getlocal or nil
local function clear_root()
  if not lv_scr_act or not lv_obj_clean then
    return
  end
  local ok, root = pcall(function()
    return lv_scr_act()
  end)
  if not ok or not root then
    return
  end
  pcall(function()
    lv_obj_clean(root)
  end)
end

if not lv_scr_act or not lv_obj_clean or not lv_canvas_create_fn then
  return
end

local root = lv_scr_act()
clear_root()

local MAIN_STYLE = rawget(_G, "LV_PART_MAIN") or 0
local CANVAS_FMT = rawget(_G, "LV_IMG_CF_TRUE_COLOR") or rawget(_G, "CANVAS_FMT_TRUE_COLOR")
local ALIGN_CENTER = rawget(_G, "LV_ALIGN_CENTER") or 0
local TIME_FONT = rawget(_G, "LV_FONT_MONTSERRAT_46") or rawget(_G, "LV_FONT_MONTSERRAT_28") or rawget(_G, "LV_FONT_MONTSERRAT_24")
local TIME_HOUR_X_OFFSET = -34
local TIME_COLON_X_OFFSET = 0
local TIME_MINUTE_X_OFFSET = 34
local TIME_Y_OFFSET = -50

local SCREEN_W = 320
local SCREEN_H = 240
local DISPLAY_COLS = 24
local DISPLAY_ROWS = 14
local DOT_SIZE = 10
local DOT_GAP = 2
local DOT_PITCH = DOT_SIZE + DOT_GAP
local MATRIX_W = DISPLAY_COLS * DOT_SIZE + (DISPLAY_COLS - 1) * DOT_GAP
local MATRIX_H = DISPLAY_ROWS * DOT_SIZE + (DISPLAY_ROWS - 1) * DOT_GAP
local MATRIX_X = math_floor((SCREEN_W - MATRIX_W) * 0.5)
local MATRIX_Y = math_floor((SCREEN_H - MATRIX_H) * 0.5)
local DISPLAY_DENSITY_BLEND = 0.5
local DISPLAY_ON_THRESHOLD = 0.15
local DISPLAY_OFF_THRESHOLD = 0.14
local DISPLAY_EDGE_MARGIN = 0.03
local DISPLAY_EDGE_CONFIRM_FRAMES = 2

local TICK_MS = 25
local GRAVITY = 16
local TILT_FULL_SCALE_DEG = 45
local IMU_X_SIGN = -1
local IMU_Y_SIGN = 1

local NUMBER_OF_PARTICLES = 220
local PARTICLE_RADIUS = 0.0155
local SPACING = 0.045
local CELL_NUM_X = 26
local CELL_NUM_Y = 17
local CELL_COUNT = CELL_NUM_X * CELL_NUM_Y
local DT = 0.016
local BOUNCYNESS = -0.9
local OVER_RELAXATION = 1.8
local STIFFNESS_COEFFICIENT = 1.0
local PUSH_ITER = 2
local GRID_ITER = 6
local FLIP_RATIO = 0.9

local FLUID_CELL = 0
local AIR_CELL = 1
local SOLID_CELL = 2

local C = {
  bg = 0x000000,
  fluid = 0x48D8FF,
  fluid_core = 0xD8FBFF,
  time = 0xFFFFFF,
  edge = 0x000000,
}

local particle_x = {}
local particle_y = {}
local particle_vx = {}
local particle_vy = {}

local u_vel = {}
local v_vel = {}
local u_prev = {}
local v_prev = {}
local u_weight = {}
local v_weight = {}
local particle_density = {}
local solid_mask = {}
local base_cell_type = {}
local cell_type = {}

local cell_particle_count_prefix = {}
local particle_pos_id = {}
local particle_cell_nr = {}
local fluid_cells = {}
local fluid_count = 0

local pressure_right = {}
local pressure_top = {}
local pressure_sx0 = {}
local pressure_sx1 = {}
local pressure_sy0 = {}
local pressure_sy1 = {}
local pressure_s = {}
local u_restore_cells = {}
local v_restore_cells = {}
local u_restore_count = 0
local v_restore_count = 0

local display_cell = {}
local display_x = {}
local display_y = {}
local display_density = {}
local display_lit = {}
local display_edge_count = {}
local display_count = 0

local invert_spacing = 1 / SPACING
local particle_rest_density = 0
local min_x = SPACING + PARTICLE_RADIUS
local min_y = SPACING + PARTICLE_RADIUS
local max_x = 0
local max_y = 0

local FX_Q = 4096
APP.CFG = {
  N = 0,
  CNX = 1,
  CNY = 2,
  CELL_COUNT = 3,
  Q = 4,
  DT_Q = 5,
  BOUNCE_Q = 6,
  MIN_X_Q = 7,
  MIN_Y_Q = 8,
  MAX_X_Q = 9,
  MAX_Y_Q = 10,
  SPACING_Q = 11,
  HALF_SPACING_Q = 12,
  PARTICLE_RADIUS_Q = 13,
  MIN_DIST_Q = 14,
  MIN_DIST2_Q = 15,
  PUSH_ITER = 16,
  GRID_ITER = 17,
  OVER_RELAX_Q = 18,
  STIFFNESS_Q = 19,
  FLIP_Q = 20,
  REST_DENSITY_Q = 21,
  FLUID_CELL = 22,
  AIR_CELL = 23,
  SOLID_CELL = 24,
  GRID_STRIDE = 25,
  DISPLAY_BLEND_Q = 26,
  COUNT = 27,
}

APP.VIPER_SRC = {}


APP.VIPER_SRC.integrate_push = [=[
void fluid_integrate_push(int32_t *p, int32_t *cfg, int32_t axq, int32_t ayq) {
  int32_t n = cfg[0];
  int32_t cnx = cfg[1];
  int32_t cny = cfg[2];
  int32_t count = cfg[3];
  int32_t q = cfg[4];
  int32_t dtq = cfg[5];
  int32_t bounceq = cfg[6];
  int32_t minx = cfg[7];
  int32_t miny = cfg[8];
  int32_t maxx = cfg[9];
  int32_t maxy = cfg[10];
  int32_t hq = cfg[11];
  int32_t vx0 = n * 2;
  int32_t vy0 = n * 3;
  int32_t cell0 = 27;
  int32_t prefix0 = 27 + n;
  int32_t pos0 = prefix0 + count + 1;
  int32_t prefix_end = prefix0 + count;
  int32_t dvx = (axq * dtq) / q;
  int32_t dvy = (ayq * dtq) / q;

  for (int32_t z = prefix0; z <= prefix_end; z = z + 1) {
    cfg[z] = 0;
  }

  for (int32_t i = 0; i < n; i = i + 1) {
    int32_t yi = n + i;
    int32_t vxi = vx0 + i;
    int32_t vyi = vy0 + i;

    int32_t vx = p[vxi] + dvx;
    int32_t vy = p[vyi] + dvy;
    int32_t x = p[i] + (vx * dtq) / q;
    int32_t y = p[yi] + (vy * dtq) / q;

    if (x < minx) { x = minx; vx = (vx * bounceq) / q; }
    if (x > maxx) { x = maxx; vx = (vx * bounceq) / q; }
    if (y < miny) { y = miny; vy = (vy * bounceq) / q; }
    if (y > maxy) { y = maxy; vy = (vy * bounceq) / q; }

    p[vxi] = vx;
    p[vyi] = vy;
    p[i] = x;
    p[yi] = y;

    int32_t xi = x / hq;
    int32_t cy = y / hq;
    if (xi < 0) { xi = 0; }
    if (xi >= cnx) { xi = cnx - 1; }
    if (cy < 0) { cy = 0; }
    if (cy >= cny) { cy = cny - 1; }

    int32_t cell = xi * cny + cy;
    int32_t pci = prefix0 + cell;
    cfg[cell0 + i] = cell;
    cfg[pci] = cfg[pci] + 1;
  }

  int32_t prefix = 0;
  for (int32_t c = 0; c < count; c = c + 1) {
    int32_t ci = prefix0 + c;
    prefix = prefix + cfg[ci];
    cfg[ci] = prefix;
  }
  cfg[prefix0 + count] = prefix;

  for (int32_t f = 0; f < n; f = f + 1) {
    int32_t fcell = cfg[cell0 + f];
    int32_t pfi = prefix0 + fcell;
    int32_t slot = cfg[pfi] - 1;
    cfg[pfi] = slot;
    cfg[pos0 + slot] = f;
  }
}
]=]

APP.VIPER_SRC.push_apply = [=[
void fluid_push_apply(int32_t *p, int32_t *cfg) {
  int32_t n = cfg[0];
  int32_t q = cfg[4];
  int32_t cnx = cfg[1];
  int32_t cny = cfg[2];
  int32_t hq = cfg[11];
  int32_t bounceq = cfg[6];
  int32_t minx = cfg[7];
  int32_t miny = cfg[8];
  int32_t maxx = cfg[9];
  int32_t maxy = cfg[10];
  int32_t min_dist = cfg[14];
  int32_t min_dist2 = cfg[15];
  int32_t iters = cfg[16];
  int32_t vx0 = n * 2;
  int32_t vy0 = n * 3;
  int32_t prefix0 = 27 + n;
  int32_t pos0 = 27 + n + cfg[3] + 1;
  int32_t halfq = q / 2;

  for (int32_t iter = 0; iter < iters; iter = iter + 1) {
    for (int32_t i = 0; i < n; i = i + 1) {
      int32_t piy = n + i;
      int32_t px = p[i];
      int32_t py = p[piy];
      int32_t pxi = px / hq;
      int32_t pyi = py / hq;
      if (pxi < 0) { pxi = 0; }
      if (pxi >= cnx) { pxi = cnx - 1; }
      if (pyi < 0) { pyi = 0; }
      if (pyi >= cny) { pyi = cny - 1; }

      int32_t x0 = pxi - 1;
      int32_t y0 = pyi - 1;
      int32_t x1 = pxi + 1;
      int32_t y1 = pyi + 1;
      if (x0 < 0) { x0 = 0; }
      if (y0 < 0) { y0 = 0; }
      if (x1 >= cnx) { x1 = cnx - 1; }
      if (y1 >= cny) { y1 = cny - 1; }

      for (int32_t gx = x0; gx <= x1; gx = gx + 1) {
        int32_t row = gx * cny;
        for (int32_t gy = y0; gy <= y1; gy = gy + 1) {
          int32_t cell = row + gy;
          int32_t first = cfg[prefix0 + cell];
          int32_t last = cfg[prefix0 + cell + 1];

          for (int32_t jj = first; jj < last; jj = jj + 1) {
            int32_t id = cfg[pos0 + jj];
            if (id != i) {
              int32_t idy = n + id;
              int32_t dx = p[id] - px;
              int32_t dy = p[idy] - py;
              int32_t d2 = dx * dx + dy * dy;

              if (d2 > 0) {
                if (d2 <= min_dist2) {
                  int32_t d = d2;
                  if (d < 1) { d = 1; }

                  for (int32_t k = 0; k < 6; k = k + 1) {
                    d = (d + d2 / d) / 2;
                    if (d < 1) { d = 1; }
                  }

                  if (d < min_dist) {
                    int32_t s = ((min_dist - d) * halfq) / d;
                    int32_t ox = (dx * s) / q;
                    int32_t oy = (dy * s) / q;
                    p[i] = p[i] - ox;
                    p[piy] = p[piy] - oy;
                    p[id] = p[id] + ox;
                    p[idy] = p[idy] + oy;
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  for (int32_t b = 0; b < n; b = b + 1) {
    int32_t by0 = n + b;
    int32_t bvx = vx0 + b;
    int32_t bvy = vy0 + b;
    int32_t bx = p[b];
    int32_t by = p[by0];

    if (bx < minx) { bx = minx; p[bvx] = (p[bvx] * bounceq) / q; }
    if (bx > maxx) { bx = maxx; p[bvx] = (p[bvx] * bounceq) / q; }
    if (by < miny) { by = miny; p[bvy] = (p[bvy] * bounceq) / q; }
    if (by > maxy) { by = maxy; p[bvy] = (p[bvy] * bounceq) / q; }

    p[b] = bx;
    p[by0] = by;
  }
}
]=]

APP.VIPER_SRC.clear_scatter = [=[
void fluid_p2g_clear_scatter(int32_t *p, int32_t *g, uint8_t *ct, uint8_t *base, int32_t *cfg) {
  int32_t n = cfg[0];
  int32_t cnx = cfg[1];
  int32_t cny = cfg[2];
  int32_t count = cfg[3];
  int32_t q = cfg[4];
  int32_t hq = cfg[11];
  int32_t half = cfg[12];
  int32_t stride = cfg[25];
  int32_t x_max = cnx - 2;
  int32_t y_max = cny - 2;
  int32_t vx0 = n * 2;
  int32_t vy0 = n * 3;
  int32_t vv0 = stride;
  int32_t uw0 = stride * 4;
  int32_t vw0 = stride * 5;
  int32_t pd0 = stride * 6;
  int32_t fluid_cell = cfg[22];

  for (int32_t ci = 0; ci < count; ci = ci + 1) {
    g[ci] = 0;
    g[vv0 + ci] = 0;
    g[uw0 + ci] = 0;
    g[vw0 + ci] = 0;
    g[pd0 + ci] = 0;
    ct[ci] = base[ci];
  }

  for (int32_t pi = 0; pi < n; pi = pi + 1) {
    int32_t py0 = n + pi;
    int32_t x = p[pi];
    int32_t y = p[py0];
    int32_t xh = x - half;
    int32_t yh = y - half;

    int32_t xi_raw = x / hq;
    int32_t yi_raw = y / hq;
    int32_t xh_raw = xh / hq;
    int32_t yh_raw = yh / hq;

    int32_t xi = xi_raw;
    int32_t yi = yi_raw;
    if (xi < 0) { xi = 0; }
    if (xi >= cnx) { xi = cnx - 1; }
    if (yi < 0) { yi = 0; }
    if (yi >= cny) { yi = cny - 1; }
    ct[xi * cny + yi] = fluid_cell;

    int32_t x0h = xh_raw;
    int32_t y0h = yh_raw;
    int32_t x0x = xi_raw;
    int32_t y0y = yi_raw;

    if (x0h < 0) { x0h = 0; }
    if (x0h > x_max) { x0h = x_max; }
    if (y0h < 0) { y0h = 0; }
    if (y0h > y_max) { y0h = y_max; }

    if (x0x < 0) { x0x = 0; }
    if (x0x > x_max) { x0x = x_max; }
    if (y0y < 0) { y0y = 0; }
    if (y0y > y_max) { y0y = y_max; }

    int32_t txh = (xh - x0h * hq) * q / hq;
    int32_t tyh = (yh - y0h * hq) * q / hq;
    int32_t txx = (x - x0x * hq) * q / hq;
    int32_t tyy = (y - y0y * hq) * q / hq;

    int32_t sxh = q - txh;
    int32_t syh = q - tyh;
    int32_t sxx = q - txx;
    int32_t syy = q - tyy;

    int32_t w0 = (sxh * syh) / q;
    int32_t w1 = (txh * syh) / q;
    int32_t w2 = (txh * tyh) / q;
    int32_t w3 = (sxh * tyh) / q;
    int32_t nr0 = x0h * cny + y0h;
    int32_t nr1 = nr0 + cny;
    int32_t nr2 = nr1 + 1;
    int32_t nr3 = nr0 + 1;

    g[pd0 + nr0] = g[pd0 + nr0] + w0;
    g[pd0 + nr1] = g[pd0 + nr1] + w1;
    g[pd0 + nr2] = g[pd0 + nr2] + w2;
    g[pd0 + nr3] = g[pd0 + nr3] + w3;

    w0 = (sxx * syh) / q;
    w1 = (txx * syh) / q;
    w2 = (txx * tyh) / q;
    w3 = (sxx * tyh) / q;
    nr0 = x0x * cny + y0h;
    nr1 = nr0 + cny;
    nr2 = nr1 + 1;
    nr3 = nr0 + 1;

    int32_t pv = p[vx0 + pi];
    g[nr0] = g[nr0] + (pv * w0) / q;
    g[uw0 + nr0] = g[uw0 + nr0] + w0;
    g[nr1] = g[nr1] + (pv * w1) / q;
    g[uw0 + nr1] = g[uw0 + nr1] + w1;
    g[nr2] = g[nr2] + (pv * w2) / q;
    g[uw0 + nr2] = g[uw0 + nr2] + w2;
    g[nr3] = g[nr3] + (pv * w3) / q;
    g[uw0 + nr3] = g[uw0 + nr3] + w3;

    w0 = (sxh * syy) / q;
    w1 = (txh * syy) / q;
    w2 = (txh * tyy) / q;
    w3 = (sxh * tyy) / q;
    nr0 = x0h * cny + y0y;
    nr1 = nr0 + cny;
    nr2 = nr1 + 1;
    nr3 = nr0 + 1;

    pv = p[vy0 + pi];
    g[vv0 + nr0] = g[vv0 + nr0] + (pv * w0) / q;
    g[vw0 + nr0] = g[vw0 + nr0] + w0;
    g[vv0 + nr1] = g[vv0 + nr1] + (pv * w1) / q;
    g[vw0 + nr1] = g[vw0 + nr1] + w1;
    g[vv0 + nr2] = g[vv0 + nr2] + (pv * w2) / q;
    g[vw0 + nr2] = g[vw0 + nr2] + w2;
    g[vv0 + nr3] = g[vv0 + nr3] + (pv * w3) / q;
    g[vw0 + nr3] = g[vw0 + nr3] + w3;
  }
}
]=]

APP.VIPER_SRC.finish = [=[
void fluid_p2g_finish(int32_t *g, uint8_t *ct, uint8_t *base, uint16_t *fluid, uint32_t *stats, int32_t *cfg) {
  int32_t cnx = cfg[1];
  int32_t cny = cfg[2];
  int32_t count = cfg[3];
  int32_t q = cfg[4];
  int32_t stride = cfg[25];
  int32_t vv0 = stride;
  int32_t up0 = stride * 2;
  int32_t vp0 = stride * 3;
  int32_t uw0 = stride * 4;
  int32_t vw0 = stride * 5;
  int32_t pd0 = stride * 6;
  int32_t fluid_count = 0;
  int32_t sum_density = 0;
  int32_t solid = cfg[24];
  int32_t fluid_cell = cfg[22];

  for (int32_t x = 1; x < cnx - 1; x = x + 1) {
    int32_t row = x * cny;
    for (int32_t y = 1; y < cny - 1; y = y + 1) {
      int32_t idx = row + y;
      if (ct[idx] == fluid_cell) {
        fluid[fluid_count] = idx;
        fluid_count = fluid_count + 1;
        sum_density = sum_density + g[pd0 + idx];
      }
    }
  }

  if (cfg[21] == 0) {
    if (fluid_count > 0) {
      cfg[21] = sum_density / fluid_count;
    }
  }

  for (int32_t i = 0; i < count; i = i + 1) {
    int32_t uwi = uw0 + i;
    int32_t vwi = vw0 + i;
    int32_t vvi_norm = vv0 + i;

    int32_t w = g[uwi];
    if (w > 0) { g[i] = (g[i] * q) / w; }

    w = g[vwi];
    if (w > 0) { g[vvi_norm] = (g[vvi_norm] * q) / w; }
  }

  for (int32_t x2 = 0; x2 < cnx; x2 = x2 + 1) {
    int32_t row2 = x2 * cny;
    for (int32_t y2 = 0; y2 < cny; y2 = y2 + 1) {
      int32_t idx2 = row2 + y2;
      int32_t vvi_wall = vv0 + idx2;

      if (base[idx2] == solid) {
        g[idx2] = g[up0 + idx2];
        g[vvi_wall] = g[vp0 + idx2];
      } else {
        if (x2 > 0) {
          if (base[idx2 - cny] == solid) { g[idx2] = g[up0 + idx2]; }
        }
        if (y2 > 0) {
          if (base[idx2 - 1] == solid) { g[vvi_wall] = g[vp0 + idx2]; }
        }
      }
    }
  }

  stats[0] = fluid_count;
}
]=]

APP.VIPER_SRC.force = [=[
void fluid_grid_forces(int32_t *g, uint8_t *base, uint16_t *fluid, uint32_t *stats, int32_t *cfg) {
  int32_t cny = cfg[2];
  int32_t count = cfg[3];
  int32_t q = cfg[4];
  int32_t iters = cfg[17];
  int32_t relax = cfg[18];
  int32_t stiffness = cfg[19];
  int32_t rest = cfg[21];
  int32_t stride = cfg[25];
  int32_t vv0 = stride;
  int32_t up0 = stride * 2;
  int32_t vp0 = stride * 3;
  int32_t pd0 = stride * 6;
  int32_t solid = cfg[24];
  int32_t fluid_count = stats[0];

  for (int32_t i = 0; i < count; i = i + 1) {
    g[up0 + i] = g[i];
    g[vp0 + i] = g[vv0 + i];
  }

  if (rest > 0) {
    for (int32_t iter = 0; iter < iters; iter = iter + 1) {
      for (int32_t n = 0; n < fluid_count; n = n + 1) {
        int32_t center = fluid[n];
        int32_t right = center + cny;
        int32_t top = center + 1;
        int32_t vv_center = vv0 + center;
        int32_t vv_top = vv0 + top;

        int32_t sx0 = 1;
        int32_t sx1 = 1;
        int32_t sy0 = 1;
        int32_t sy1 = 1;

        if (base[center - cny] == solid) { sx0 = 0; }
        if (base[right] == solid) { sx1 = 0; }
        if (base[center - 1] == solid) { sy0 = 0; }
        if (base[top] == solid) { sy1 = 0; }

        int32_t s = sx0 + sx1 + sy0 + sy1;
        if (s != 0) {
          int32_t div = g[right] - g[center] + g[vv_top] - g[vv_center];
          int32_t compression = g[pd0 + center] - rest;
          if (compression > 0) { div = div - (compression * stiffness) / q; }

          int32_t qs = q * s;
          int32_t pp = 0 - ((div * relax) / qs);

          g[center] = g[center] - sx0 * pp;
          g[right] = g[right] + sx1 * pp;
          g[vv_center] = g[vv_center] - sy0 * pp;
          g[vv_top] = g[vv_top] + sy1 * pp;
        }
      }
    }
  } else {
    for (int32_t iter2 = 0; iter2 < iters; iter2 = iter2 + 1) {
      for (int32_t n2 = 0; n2 < fluid_count; n2 = n2 + 1) {
        int32_t center2 = fluid[n2];
        int32_t right2 = center2 + cny;
        int32_t top2 = center2 + 1;
        int32_t vv_center2 = vv0 + center2;
        int32_t vv_top2 = vv0 + top2;

        int32_t sx02 = 1;
        int32_t sx12 = 1;
        int32_t sy02 = 1;
        int32_t sy12 = 1;

        if (base[center2 - cny] == solid) { sx02 = 0; }
        if (base[right2] == solid) { sx12 = 0; }
        if (base[center2 - 1] == solid) { sy02 = 0; }
        if (base[top2] == solid) { sy12 = 0; }

        int32_t s2 = sx02 + sx12 + sy02 + sy12;
        if (s2 != 0) {
          int32_t div2 = g[right2] - g[center2] + g[vv_top2] - g[vv_center2];
          int32_t qs2 = q * s2;
          int32_t pp2 = 0 - ((div2 * relax) / qs2);

          g[center2] = g[center2] - sx02 * pp2;
          g[right2] = g[right2] + sx12 * pp2;
          g[vv_center2] = g[vv_center2] - sy02 * pp2;
          g[vv_top2] = g[vv_top2] + sy12 * pp2;
        }
      }
    }
  }
}
]=]

APP.VIPER_SRC.g2p = [=[
void fluid_g2p(int32_t *p, int32_t *g, uint8_t *ct, int32_t *cfg) {
  int32_t n = cfg[0];
  int32_t cnx = cfg[1];
  int32_t cny = cfg[2];
  int32_t q = cfg[4];
  int32_t hq = cfg[11];
  int32_t half = cfg[12];
  int32_t flip = cfg[20];
  int32_t qflip = q - flip;
  int32_t stride = cfg[25];
  int32_t air = cfg[23];
  int32_t x_max = cnx - 2;
  int32_t y_max = cny - 2;
  int32_t vx0 = n * 2;
  int32_t vy0 = n * 3;
  int32_t vv0 = stride;
  int32_t up0 = stride * 2;
  int32_t vp0 = stride * 3;

  for (int32_t i = 0; i < n; i = i + 1) {
    int32_t py0 = n + i;
    int32_t x = p[i];
    int32_t y = p[py0];
    int32_t xh = x - half;
    int32_t yh = y - half;

    int32_t xi_raw = x / hq;
    int32_t yi_raw = y / hq;
    int32_t xh_raw = xh / hq;
    int32_t yh_raw = yh / hq;

    int32_t x0x = xi_raw;
    int32_t y0h = yh_raw;
    if (x0x < 0) { x0x = 0; }
    if (x0x > x_max) { x0x = x_max; }
    if (y0h < 0) { y0h = 0; }
    if (y0h > y_max) { y0h = y_max; }

    int32_t txx = (x - x0x * hq) * q / hq;
    int32_t tyh = (yh - y0h * hq) * q / hq;
    int32_t sxx = q - txx;
    int32_t syh = q - tyh;

    int32_t d0 = (sxx * syh) / q;
    int32_t d1 = (txx * syh) / q;
    int32_t d2 = (txx * tyh) / q;
    int32_t d3 = (sxx * tyh) / q;

    int32_t nr0 = x0x * cny + y0h;
    int32_t nr1 = nr0 + cny;
    int32_t nr2 = nr1 + 1;
    int32_t nr3 = nr0 + 1;

    int32_t v0 = 0;
    int32_t v1 = 0;
    int32_t v2 = 0;
    int32_t v3 = 0;

    if (ct[nr0] != air) { v0 = 1; } else { if (nr0 >= cny) { if (ct[nr0 - cny] != air) { v0 = 1; } } }
    if (ct[nr1] != air) { v1 = 1; } else { if (nr1 >= cny) { if (ct[nr1 - cny] != air) { v1 = 1; } } }
    if (ct[nr2] != air) { v2 = 1; } else { if (nr2 >= cny) { if (ct[nr2 - cny] != air) { v2 = 1; } } }
    if (ct[nr3] != air) { v3 = 1; } else { if (nr3 >= cny) { if (ct[nr3 - cny] != air) { v3 = 1; } } }

    int32_t d = 0;
    int32_t pic_num = 0;
    int32_t corr_num = 0;
    int32_t gv = 0;
    int32_t gi = 0;

    if (v0 != 0) {
      gv = g[nr0];
      d = d + d0;
      pic_num = pic_num + d0 * gv;
      corr_num = corr_num + d0 * (gv - g[up0 + nr0]);
    }
    if (v1 != 0) {
      gv = g[nr1];
      d = d + d1;
      pic_num = pic_num + d1 * gv;
      corr_num = corr_num + d1 * (gv - g[up0 + nr1]);
    }
    if (v2 != 0) {
      gv = g[nr2];
      d = d + d2;
      pic_num = pic_num + d2 * gv;
      corr_num = corr_num + d2 * (gv - g[up0 + nr2]);
    }
    if (v3 != 0) {
      gv = g[nr3];
      d = d + d3;
      pic_num = pic_num + d3 * gv;
      corr_num = corr_num + d3 * (gv - g[up0 + nr3]);
    }

    if (d > 0) {
      int32_t pic = pic_num / d;
      int32_t corr = corr_num / d;
      int32_t pvi_x = vx0 + i;
      p[pvi_x] = (qflip * pic + flip * (p[pvi_x] + corr)) / q;
    }

    int32_t x0h = xh_raw;
    int32_t y0y = yi_raw;
    if (x0h < 0) { x0h = 0; }
    if (x0h > x_max) { x0h = x_max; }
    if (y0y < 0) { y0y = 0; }
    if (y0y > y_max) { y0y = y_max; }

    int32_t txh = (xh - x0h * hq) * q / hq;
    int32_t tyy = (y - y0y * hq) * q / hq;
    int32_t sxh = q - txh;
    int32_t syy = q - tyy;

    d0 = (sxh * syy) / q;
    d1 = (txh * syy) / q;
    d2 = (txh * tyy) / q;
    d3 = (sxh * tyy) / q;

    nr0 = x0h * cny + y0y;
    nr1 = nr0 + cny;
    nr2 = nr1 + 1;
    nr3 = nr0 + 1;

    v0 = 0;
    v1 = 0;
    v2 = 0;
    v3 = 0;

    if (ct[nr0] != air) { v0 = 1; } else { if (nr0 > 0) { if (ct[nr0 - 1] != air) { v0 = 1; } } }
    if (ct[nr1] != air) { v1 = 1; } else { if (nr1 > 0) { if (ct[nr1 - 1] != air) { v1 = 1; } } }
    if (ct[nr2] != air) { v2 = 1; } else { if (nr2 > 0) { if (ct[nr2 - 1] != air) { v2 = 1; } } }
    if (ct[nr3] != air) { v3 = 1; } else { if (nr3 > 0) { if (ct[nr3 - 1] != air) { v3 = 1; } } }

    d = 0;
    pic_num = 0;
    corr_num = 0;

    if (v0 != 0) {
      gi = vv0 + nr0;
      gv = g[gi];
      d = d + d0;
      pic_num = pic_num + d0 * gv;
      corr_num = corr_num + d0 * (gv - g[vp0 + nr0]);
    }
    if (v1 != 0) {
      gi = vv0 + nr1;
      gv = g[gi];
      d = d + d1;
      pic_num = pic_num + d1 * gv;
      corr_num = corr_num + d1 * (gv - g[vp0 + nr1]);
    }
    if (v2 != 0) {
      gi = vv0 + nr2;
      gv = g[gi];
      d = d + d2;
      pic_num = pic_num + d2 * gv;
      corr_num = corr_num + d2 * (gv - g[vp0 + nr2]);
    }
    if (v3 != 0) {
      gi = vv0 + nr3;
      gv = g[gi];
      d = d + d3;
      pic_num = pic_num + d3 * gv;
      corr_num = corr_num + d3 * (gv - g[vp0 + nr3]);
    }

    if (d > 0) {
      int32_t pic_y = pic_num / d;
      int32_t corr_y = corr_num / d;
      int32_t pvi_y = vy0 + i;
      p[pvi_y] = (qflip * pic_y + flip * (p[pvi_y] + corr_y)) / q;
    }
  }
}
]=]


local canvas = nil
local time_hour_label = nil
local time_colon_label = nil
local time_minute_label = nil
local time_colon_visible = true
local rect_mode = 0
local rect_dsc = {
  bg_color = C.fluid,
  bg_opa = 255,
  radius = 2,
  border_width = 0,
}
local canvas_needs_full_redraw = true

local accel_x = 0
local accel_y = GRAVITY
local target_accel_x = 0
local target_accel_y = GRAVITY
local imu_registered = false
local profile_state = {
  draw_last_us = 0,
  draw_total_us = 0,
  draw_api_us = 0,
  draw_end_us = 0,
  draw_walk_us = 0,
  draw_frames = 0,
}

local function clamp(v, lo, hi)
  if v < lo then
    return lo
  end
  if v > hi then
    return hi
  end
  return v
end

local function cell_index(x, y)
  return x * CELL_NUM_Y + y + 1
end

local function fill_array(t, count, value)
  for i = 1, count do
    t[i] = value
  end
end

local function init_sim_bounds()
  invert_spacing = 1.0 / SPACING
  min_x = SPACING + PARTICLE_RADIUS
  min_y = SPACING + PARTICLE_RADIUS
  max_x = (CELL_NUM_X - 1) * SPACING - PARTICLE_RADIUS
  max_y = (CELL_NUM_Y - 1) * SPACING - PARTICLE_RADIUS
end

local function base_type_for_cell(x, y)
  if x == 0 or x == CELL_NUM_X - 1 or y == 0 or y == CELL_NUM_Y - 1 then
    return SOLID_CELL
  end
  return AIR_CELL
end

local function init_display_state()
  fill_array(display_density, CELL_COUNT, 0)
  fill_array(display_lit, CELL_COUNT, false)
  fill_array(display_edge_count, CELL_COUNT, 0)
end

local function now_us()
  if tmr_now_fn then
    return tmr_now_fn()
  end
  if millis_fn then
    return millis_fn() * 1000
  end
  return nil
end

local function elapsed_us(t0, t1)
  if not t0 or not t1 then
    return 0
  end
  if t1 >= t0 then
    return t1 - t0
  end
  return (4294967296 - t0) + t1
end

local function profile_draw(total_us, api_us, end_us)
  local t1 = now_us()
  if not t1 or not total_us then
    return
  end

  api_us = api_us or 0
  end_us = end_us or 0
  profile_state.draw_total_us = profile_state.draw_total_us + total_us
  profile_state.draw_api_us = profile_state.draw_api_us + api_us
  profile_state.draw_end_us = profile_state.draw_end_us + end_us
  profile_state.draw_walk_us = profile_state.draw_walk_us + (total_us - api_us)
  profile_state.draw_frames = profile_state.draw_frames + 1

  if profile_state.draw_last_us == 0 then
    profile_state.draw_last_us = t1
    return
  end

  if elapsed_us(profile_state.draw_last_us, t1) >= 1000000 then
    if print and profile_state.draw_frames > 0 and profile_state.draw_total_us > 0 then
      local avg_us = profile_state.draw_total_us / profile_state.draw_frames
      local api_avg_us = profile_state.draw_api_us / profile_state.draw_frames
      local end_avg_us = profile_state.draw_end_us / profile_state.draw_frames
      local walk_avg_us = profile_state.draw_walk_us / profile_state.draw_frames
      local fps = 1000000 / avg_us
      print(
        "[FluidPendant] draw fps",
        math_floor(fps + 0.5),
        "avg_ms",
        math_floor(avg_us / 100 + 0.5) / 10,
        "api_ms",
        math_floor(api_avg_us / 100 + 0.5) / 10,
        "end_ms",
        math_floor(end_avg_us / 100 + 0.5) / 10,
        "walk_ms",
        math_floor(walk_avg_us / 100 + 0.5) / 10
      )
    end
    profile_state.draw_last_us = t1
    profile_state.draw_total_us = 0
    profile_state.draw_api_us = 0
    profile_state.draw_end_us = 0
    profile_state.draw_walk_us = 0
    profile_state.draw_frames = 0
  end
end

local function get_time_parts()
  local hour = 8
  local minute = 0

  if time_getlocal_fn then
    local ok, tm = pcall_fn(time_getlocal_fn)
    if ok and tm then
      hour = tonumber(tm.hour) or hour
      minute = tonumber(tm.min) or minute
    end
  end

  return hour, minute
end

local function update_time_label()
  if not time_hour_label or not time_colon_label or not time_minute_label or not lv_label_set_text_fn then
    return
  end

  local hour, minute = get_time_parts()
  pcall_fn(lv_label_set_text_fn, time_hour_label, string_format("%02d", hour))
  pcall_fn(lv_label_set_text_fn, time_minute_label, string_format("%02d", minute))

  if lv_obj_set_style_text_opa_fn then
    pcall_fn(lv_label_set_text_fn, time_colon_label, ":")
    pcall_fn(lv_obj_set_style_text_opa_fn, time_colon_label, time_colon_visible and 255 or 0, MAIN_STYLE)
  else
    pcall_fn(lv_label_set_text_fn, time_colon_label, time_colon_visible and ":" or "")
  end

  if lv_obj_align_fn then
    pcall_fn(lv_obj_align_fn, time_hour_label, ALIGN_CENTER, TIME_HOUR_X_OFFSET, TIME_Y_OFFSET)
    pcall_fn(lv_obj_align_fn, time_colon_label, ALIGN_CENTER, TIME_COLON_X_OFFSET, TIME_Y_OFFSET)
    pcall_fn(lv_obj_align_fn, time_minute_label, ALIGN_CENTER, TIME_MINUTE_X_OFFSET, TIME_Y_OFFSET)
  end
end

local function setup_solid_mask()
  u_restore_count = 0
  v_restore_count = 0

  for x = 0, CELL_NUM_X - 1 do
    for y = 0, CELL_NUM_Y - 1 do
      local base_type = base_type_for_cell(x, y)
      local idx = x * CELL_NUM_Y + y + 1
      solid_mask[idx] = (base_type == SOLID_CELL) and 0 or 1
      base_cell_type[idx] = base_type
    end
  end

  for x = 0, CELL_NUM_X - 1 do
    for y = 0, CELL_NUM_Y - 1 do
      local idx = x * CELL_NUM_Y + y + 1
      local solid = base_cell_type[idx] == SOLID_CELL
      local left_solid = x > 0 and base_cell_type[(x - 1) * CELL_NUM_Y + y + 1] == SOLID_CELL
      local bottom_solid = y > 0 and base_cell_type[x * CELL_NUM_Y + y] == SOLID_CELL

      if solid or left_solid then
        u_restore_count = u_restore_count + 1
        u_restore_cells[u_restore_count] = idx
      end
      if solid or bottom_solid then
        v_restore_count = v_restore_count + 1
        v_restore_cells[v_restore_count] = idx
      end
    end
  end

  for x = 1, CELL_NUM_X - 2 do
    for y = 1, CELL_NUM_Y - 2 do
      local center = x * CELL_NUM_Y + y + 1
      local left = (x - 1) * CELL_NUM_Y + y + 1
      local right = (x + 1) * CELL_NUM_Y + y + 1
      local bottom = x * CELL_NUM_Y + (y - 1) + 1
      local top = x * CELL_NUM_Y + (y + 1) + 1
      local sx0 = solid_mask[left]
      local sx1 = solid_mask[right]
      local sy0 = solid_mask[bottom]
      local sy1 = solid_mask[top]

      pressure_right[center] = right
      pressure_top[center] = top
      pressure_sx0[center] = sx0
      pressure_sx1[center] = sx1
      pressure_sy0[center] = sy0
      pressure_sy1[center] = sy1
      pressure_s[center] = sx0 + sx1 + sy0 + sy1
    end
  end
end

local function build_display_lookup()
  display_count = 0
  for y = 1, CELL_NUM_Y - 2 do
    for x = 1, CELL_NUM_X - 2 do
      display_count = display_count + 1
      display_cell[display_count] = cell_index(x, y)
      display_x[display_count] = MATRIX_X + (x - 1) * DOT_PITCH
      display_y[display_count] = MATRIX_Y + (y - 1) * DOT_PITCH
    end
  end
end

local function init_particles()
  fill_array(particle_x, NUMBER_OF_PARTICLES, SPACING + PARTICLE_RADIUS)
  fill_array(particle_y, NUMBER_OF_PARTICLES, SPACING + PARTICLE_RADIUS)
  fill_array(particle_vx, NUMBER_OF_PARTICLES, 0)
  fill_array(particle_vy, NUMBER_OF_PARTICLES, 0)

  fill_array(u_vel, CELL_COUNT, 0)
  fill_array(v_vel, CELL_COUNT, 0)
  fill_array(u_prev, CELL_COUNT, 0)
  fill_array(v_prev, CELL_COUNT, 0)
  fill_array(u_weight, CELL_COUNT, 0)
  fill_array(v_weight, CELL_COUNT, 0)
  fill_array(particle_density, CELL_COUNT, 0)
  fill_array(cell_type, CELL_COUNT, FLUID_CELL)
  init_display_state()

  particle_rest_density = 0
  init_sim_bounds()
  setup_solid_mask()

  local h = SPACING
  local r = PARTICLE_RADIUS
  local dx = 2.0 * r
  local dy = 0.86602540378 * dx

  local p_num = 1
  for i = 0, CELL_NUM_X - 1 do
    for j = 0, CELL_NUM_Y - 1 do
      if p_num <= NUMBER_OF_PARTICLES then
        local px = h + r + dx * i + ((j % 2 == 0) and 0 or r)
        local py = h + r + dy * j
        if px <= (CELL_NUM_X - 1) * h - r and py <= (CELL_NUM_Y - 1) * h - r then
          particle_x[p_num] = px
          particle_y[p_num] = py
          p_num = p_num + 1
        end
      end
    end
  end
end

function APP.qnum(v)
  if v >= 0 then
    return math_floor(v * FX_Q + 0.5)
  end
  return -math_floor((-v) * FX_Q + 0.5)
end

local function init_viper_particles(ctx)
  local default_pos = APP.qnum(SPACING + PARTICLE_RADIUS)

  for i = 1, NUMBER_OF_PARTICLES do
    ctx.p:set32(i - 1, default_pos)
    ctx.p:set32(NUMBER_OF_PARTICLES + i - 1, default_pos)
    ctx.p:set32(NUMBER_OF_PARTICLES * 2 + i - 1, 0)
    ctx.p:set32(NUMBER_OF_PARTICLES * 3 + i - 1, 0)
  end

  local h = SPACING
  local r = PARTICLE_RADIUS
  local dx = 2.0 * r
  local dy = 0.86602540378 * dx

  local p_num = 1
  for i = 0, CELL_NUM_X - 1 do
    for j = 0, CELL_NUM_Y - 1 do
      if p_num <= NUMBER_OF_PARTICLES then
        local px = h + r + dx * i + ((j % 2 == 0) and 0 or r)
        local py = h + r + dy * j
        if px <= (CELL_NUM_X - 1) * h - r and py <= (CELL_NUM_Y - 1) * h - r then
          ctx.p:set32(p_num - 1, APP.qnum(px))
          ctx.p:set32(NUMBER_OF_PARTICLES + p_num - 1, APP.qnum(py))
          p_num = p_num + 1
        end
      end
    end
  end
end

function APP.init_viper_engine()
  local viper_mod = rawget(_G, "viper")
  if not viper_mod or not viper_mod.compile_c or not viper_mod.buf then
    return false
  end

  init_sim_bounds()

  local ok, ctx_or_err = pcall_fn(function()
    local ctx = {}
    ctx.p = viper_mod.buf(NUMBER_OF_PARTICLES * 4 * 4)
    ctx.g = viper_mod.buf(CELL_COUNT * 7 * 4)
    ctx.ct = viper_mod.buf(CELL_COUNT)
    ctx.base = viper_mod.buf(CELL_COUNT)
    ctx.fluid = viper_mod.buf(CELL_COUNT * 2)
    ctx.stats = viper_mod.buf(8 * 4)
    ctx.cfg = viper_mod.buf((APP.CFG.COUNT + NUMBER_OF_PARTICLES + CELL_COUNT + 1 + NUMBER_OF_PARTICLES) * 4)

    ctx.integrate_push = viper_mod.compile_c(APP.VIPER_SRC.integrate_push, { bounds = false })
    ctx.push_apply = viper_mod.compile_c(APP.VIPER_SRC.push_apply, { bounds = false })
    ctx.clear_scatter = viper_mod.compile_c(APP.VIPER_SRC.clear_scatter, { bounds = false })
    ctx.finish = viper_mod.compile_c(APP.VIPER_SRC.finish, { bounds = false })
    ctx.force = viper_mod.compile_c(APP.VIPER_SRC.force, { bounds = false })
    ctx.g2p = viper_mod.compile_c(APP.VIPER_SRC.g2p, { bounds = false })

    ctx.cfg:set32(APP.CFG.N, NUMBER_OF_PARTICLES)
    ctx.cfg:set32(APP.CFG.CNX, CELL_NUM_X)
    ctx.cfg:set32(APP.CFG.CNY, CELL_NUM_Y)
    ctx.cfg:set32(APP.CFG.CELL_COUNT, CELL_COUNT)
    ctx.cfg:set32(APP.CFG.Q, FX_Q)
    ctx.cfg:set32(APP.CFG.DT_Q, APP.qnum(DT))
    ctx.cfg:set32(APP.CFG.BOUNCE_Q, APP.qnum(BOUNCYNESS))
    ctx.cfg:set32(APP.CFG.MIN_X_Q, APP.qnum(min_x))
    ctx.cfg:set32(APP.CFG.MIN_Y_Q, APP.qnum(min_y))
    ctx.cfg:set32(APP.CFG.MAX_X_Q, APP.qnum(max_x))
    ctx.cfg:set32(APP.CFG.MAX_Y_Q, APP.qnum(max_y))
    ctx.cfg:set32(APP.CFG.SPACING_Q, APP.qnum(SPACING))
    ctx.cfg:set32(APP.CFG.HALF_SPACING_Q, APP.qnum(0.5 * SPACING))
    ctx.cfg:set32(APP.CFG.PARTICLE_RADIUS_Q, APP.qnum(PARTICLE_RADIUS))
    ctx.cfg:set32(APP.CFG.MIN_DIST_Q, APP.qnum(2.0 * PARTICLE_RADIUS))
    ctx.cfg:set32(APP.CFG.MIN_DIST2_Q, APP.qnum(2.0 * PARTICLE_RADIUS) * APP.qnum(2.0 * PARTICLE_RADIUS))
    ctx.cfg:set32(APP.CFG.PUSH_ITER, PUSH_ITER)
    ctx.cfg:set32(APP.CFG.GRID_ITER, GRID_ITER)
    ctx.cfg:set32(APP.CFG.OVER_RELAX_Q, APP.qnum(OVER_RELAXATION))
    ctx.cfg:set32(APP.CFG.STIFFNESS_Q, APP.qnum(STIFFNESS_COEFFICIENT))
    ctx.cfg:set32(APP.CFG.FLIP_Q, APP.qnum(FLIP_RATIO))
    ctx.cfg:set32(APP.CFG.REST_DENSITY_Q, 0)
    ctx.cfg:set32(APP.CFG.FLUID_CELL, FLUID_CELL)
    ctx.cfg:set32(APP.CFG.AIR_CELL, AIR_CELL)
    ctx.cfg:set32(APP.CFG.SOLID_CELL, SOLID_CELL)
    ctx.cfg:set32(APP.CFG.GRID_STRIDE, CELL_COUNT)
    ctx.cfg:set32(APP.CFG.DISPLAY_BLEND_Q, APP.qnum(DISPLAY_DENSITY_BLEND))

    init_viper_particles(ctx)

    for x = 0, CELL_NUM_X - 1 do
      local row = x * CELL_NUM_Y
      for y = 0, CELL_NUM_Y - 1 do
        local idx = row + y
        local base_type = base_type_for_cell(x, y)
        ctx.base:set8(idx, base_type)
        ctx.ct:set8(idx, base_type)
      end
    end

    return ctx
  end)

  if ok and ctx_or_err then
    APP.viper_ctx = ctx_or_err
    print("[FluidPendant] viper fixed-point engine enabled")
    return true
  end

  APP.viper_ctx = nil
  if print then
    print("[FluidPendant] viper disabled:", tostring(ctx_or_err))
  end
  return false
end

function APP.viper_particles_to_grid(ctx)
  ctx.clear_scatter(ctx.p, ctx.g, ctx.ct, ctx.base, ctx.cfg)
  ctx.finish(ctx.g, ctx.ct, ctx.base, ctx.fluid, ctx.stats, ctx.cfg)
  particle_rest_density = (ctx.cfg:get32(APP.CFG.REST_DENSITY_Q) or 0) / FX_Q
end

function APP.viper_simulation_step(ctx, x_accel, y_accel)
  ctx.integrate_push(ctx.p, ctx.cfg, APP.qnum(x_accel), APP.qnum(y_accel))
  ctx.push_apply(ctx.p, ctx.cfg)
  APP.viper_particles_to_grid(ctx)
  ctx.force(ctx.g, ctx.base, ctx.fluid, ctx.stats, ctx.cfg)
  ctx.g2p(ctx.p, ctx.g, ctx.ct, ctx.cfg)
end

local function integrate_particles(x_accel, y_accel)
  for i = 1, NUMBER_OF_PARTICLES do
    local vx = particle_vx[i] + x_accel * DT
    local vy = particle_vy[i] + y_accel * DT
    local x = particle_x[i] + vx * DT
    local y = particle_y[i] + vy * DT

    if x < min_x then
      x = min_x
      vx = vx * BOUNCYNESS
    end
    if x > max_x then
      x = max_x
      vx = vx * BOUNCYNESS
    end
    if y < min_y then
      y = min_y
      vy = vy * BOUNCYNESS
    end
    if y > max_y then
      y = max_y
      vy = vy * BOUNCYNESS
    end

    particle_vx[i] = vx
    particle_vy[i] = vy
    particle_x[i] = x
    particle_y[i] = y
  end
end

local function enforce_particle_bounds()
  for i = 1, NUMBER_OF_PARTICLES do
    local x = particle_x[i]
    local y = particle_y[i]

    if x < min_x then
      x = min_x
      particle_vx[i] = particle_vx[i] * BOUNCYNESS
    end
    if x > max_x then
      x = max_x
      particle_vx[i] = particle_vx[i] * BOUNCYNESS
    end
    if y < min_y then
      y = min_y
      particle_vy[i] = particle_vy[i] * BOUNCYNESS
    end
    if y > max_y then
      y = max_y
      particle_vy[i] = particle_vy[i] * BOUNCYNESS
    end

    particle_x[i] = x
    particle_y[i] = y
  end
end

local function push_particles_apart(n_iters)
  local px_arr = particle_x
  local py_arr = particle_y
  local prefix_arr = cell_particle_count_prefix
  local pos_id = particle_pos_id
  local particle_cell = particle_cell_nr
  local h1 = invert_spacing
  local cny = CELL_NUM_Y
  local sqrt_fn = math_sqrt

  fill_array(prefix_arr, CELL_COUNT + 1, 0)

  for i = 1, NUMBER_OF_PARTICLES do
    local xi = math_floor(px_arr[i] * h1)
    local yi = math_floor(py_arr[i] * h1)
    if xi < 0 then xi = 0 elseif xi >= CELL_NUM_X then xi = CELL_NUM_X - 1 end
    if yi < 0 then yi = 0 elseif yi >= CELL_NUM_Y then yi = CELL_NUM_Y - 1 end
    local cell_nr = xi * cny + yi + 1
    particle_cell[i] = cell_nr
    prefix_arr[cell_nr] = prefix_arr[cell_nr] + 1
  end

  local prefix = 0
  for i = 1, CELL_COUNT do
    prefix = prefix + prefix_arr[i]
    prefix_arr[i] = prefix
  end
  prefix_arr[CELL_COUNT + 1] = prefix

  for i = 1, NUMBER_OF_PARTICLES do
    local cell_nr = particle_cell[i]
    local slot = prefix_arr[cell_nr] - 1
    prefix_arr[cell_nr] = slot
    pos_id[slot + 1] = i
  end

  local min_dist = 2.0 * PARTICLE_RADIUS
  local min_dist2 = min_dist * min_dist

  for _ = 1, n_iters do
    for i = 1, NUMBER_OF_PARTICLES do
      local px = px_arr[i]
      local py = py_arr[i]
      local pxi = math_floor(px * h1)
      local pyi = math_floor(py * h1)
      if pxi < 0 then pxi = 0 elseif pxi >= CELL_NUM_X then pxi = CELL_NUM_X - 1 end
      if pyi < 0 then pyi = 0 elseif pyi >= CELL_NUM_Y then pyi = CELL_NUM_Y - 1 end
      local x0 = (pxi > 0) and (pxi - 1) or 0
      local y0 = (pyi > 0) and (pyi - 1) or 0
      local x1 = (pxi + 1 < CELL_NUM_X) and (pxi + 1) or (CELL_NUM_X - 1)
      local y1 = (pyi + 1 < CELL_NUM_Y) and (pyi + 1) or (CELL_NUM_Y - 1)

      for xi = x0, x1 do
        local row = xi * cny + 1
        for yi = y0, y1 do
          local cell_nr = row + yi
          local first_idx = prefix_arr[cell_nr]
          local last_idx = prefix_arr[cell_nr + 1]
          for j = first_idx, last_idx - 1 do
            local id = pos_id[j + 1]
            if id ~= i then
              local qx = px_arr[id]
              local qy = py_arr[id]
              local dx = qx - px
              local dy = qy - py
              local d2 = dx * dx + dy * dy
              if d2 <= min_dist2 and d2 > 0 then
                local d = sqrt_fn(d2)
                local s = 0.5 * (min_dist - d) / d
                dx = dx * s
                dy = dy * s
                px_arr[i] = px_arr[i] - dx
                py_arr[i] = py_arr[i] - dy
                px_arr[id] = px_arr[id] + dx
                py_arr[id] = py_arr[id] + dy
              end
            end
          end
        end
      end
    end
  end

  enforce_particle_bounds()
end

local function particles_to_grid()
  local px_arr = particle_x
  local py_arr = particle_y
  local pvx_arr = particle_vx
  local pvy_arr = particle_vy
  local uv = u_vel
  local vv = v_vel
  local up = u_prev
  local vp = v_prev
  local uw = u_weight
  local vw = v_weight
  local pd = particle_density
  local ct = cell_type
  local base_type = base_cell_type
  local cny = CELL_NUM_Y
  local h = SPACING
  local h1 = invert_spacing
  local h2 = 0.5 * h
  local x_max = CELL_NUM_X - 2
  local y_max = CELL_NUM_Y - 2

  for i = 1, CELL_COUNT do
    uv[i] = 0
    vv[i] = 0
    uw[i] = 0
    vw[i] = 0
    pd[i] = 0
    ct[i] = base_type[i]
  end

  for i = 1, NUMBER_OF_PARTICLES do
    local x = px_arr[i]
    local y = py_arr[i]

    local xi = math_floor(x * h1)
    local yi = math_floor(y * h1)
    if xi < 0 then xi = 0 elseif xi >= CELL_NUM_X then xi = CELL_NUM_X - 1 end
    if yi < 0 then yi = 0 elseif yi >= CELL_NUM_Y then yi = CELL_NUM_Y - 1 end
    local fluid_idx = xi * cny + yi + 1
    if ct[fluid_idx] ~= FLUID_CELL then
      ct[fluid_idx] = FLUID_CELL
    end

    local x0 = math_floor((x - h2) * h1)
    local y0 = math_floor((y - h2) * h1)
    if x0 < 0 then x0 = 0 elseif x0 > x_max then x0 = x_max end
    if y0 < 0 then y0 = 0 elseif y0 > y_max then y0 = y_max end
    local tx = ((x - h2) - x0 * h) * h1
    local ty = ((y - h2) - y0 * h) * h1
    local sx = 1.0 - tx
    local sy = 1.0 - ty
    local w0 = sx * sy
    local w1 = tx * sy
    local w2 = tx * ty
    local w3 = sx * ty
    local nr0 = x0 * cny + y0 + 1
    local nr1 = nr0 + cny
    local nr2 = nr1 + 1
    local nr3 = nr0 + 1
    pd[nr0] = pd[nr0] + w0
    pd[nr1] = pd[nr1] + w1
    pd[nr2] = pd[nr2] + w2
    pd[nr3] = pd[nr3] + w3

    x0 = math_floor(x * h1)
    y0 = math_floor((y - h2) * h1)
    if x0 < 0 then x0 = 0 elseif x0 > x_max then x0 = x_max end
    if y0 < 0 then y0 = 0 elseif y0 > y_max then y0 = y_max end
    tx = (x - x0 * h) * h1
    ty = ((y - h2) - y0 * h) * h1
    sx = 1.0 - tx
    sy = 1.0 - ty
    w0 = sx * sy
    w1 = tx * sy
    w2 = tx * ty
    w3 = sx * ty
    nr0 = x0 * cny + y0 + 1
    nr1 = nr0 + cny
    nr2 = nr1 + 1
    nr3 = nr0 + 1
    local pv = pvx_arr[i]
    uv[nr0] = uv[nr0] + pv * w0
    uw[nr0] = uw[nr0] + w0
    uv[nr1] = uv[nr1] + pv * w1
    uw[nr1] = uw[nr1] + w1
    uv[nr2] = uv[nr2] + pv * w2
    uw[nr2] = uw[nr2] + w2
    uv[nr3] = uv[nr3] + pv * w3
    uw[nr3] = uw[nr3] + w3

    x0 = math_floor((x - h2) * h1)
    y0 = math_floor(y * h1)
    if x0 < 0 then x0 = 0 elseif x0 > x_max then x0 = x_max end
    if y0 < 0 then y0 = 0 elseif y0 > y_max then y0 = y_max end
    tx = ((x - h2) - x0 * h) * h1
    ty = (y - y0 * h) * h1
    sx = 1.0 - tx
    sy = 1.0 - ty
    w0 = sx * sy
    w1 = tx * sy
    w2 = tx * ty
    w3 = sx * ty
    nr0 = x0 * cny + y0 + 1
    nr1 = nr0 + cny
    nr2 = nr1 + 1
    nr3 = nr0 + 1
    pv = pvy_arr[i]
    vv[nr0] = vv[nr0] + pv * w0
    vw[nr0] = vw[nr0] + w0
    vv[nr1] = vv[nr1] + pv * w1
    vw[nr1] = vw[nr1] + w1
    vv[nr2] = vv[nr2] + pv * w2
    vw[nr2] = vw[nr2] + w2
    vv[nr3] = vv[nr3] + pv * w3
    vw[nr3] = vw[nr3] + w3
  end

  fluid_count = 0
  for x = 1, CELL_NUM_X - 2 do
    local row = x * cny + 1
    for y = 1, CELL_NUM_Y - 2 do
      local idx = row + y
      if ct[idx] == FLUID_CELL then
        fluid_count = fluid_count + 1
        fluid_cells[fluid_count] = idx
      end
    end
  end

  if particle_rest_density == 0 then
    local sum = 0
    for i = 1, fluid_count do
      sum = sum + pd[fluid_cells[i]]
    end
    if fluid_count > 0 then
      particle_rest_density = sum / fluid_count
    end
  end

  for i = 1, CELL_COUNT do
    local w = uw[i]
    if w > 0 then
      uv[i] = uv[i] / w
    end
    w = vw[i]
    if w > 0 then
      vv[i] = vv[i] / w
    end
  end

  for i = 1, u_restore_count do
    local idx = u_restore_cells[i]
    uv[idx] = up[idx]
  end
  for i = 1, v_restore_count do
    local idx = v_restore_cells[i]
    vv[idx] = vp[idx]
  end
end

local function compute_grid_forces(n_iters)
  local uv = u_vel
  local vv = v_vel
  local up = u_prev
  local vp = v_prev
  local pd = particle_density
  local cells = fluid_cells
  local right_arr = pressure_right
  local top_arr = pressure_top
  local sx0_arr = pressure_sx0
  local sx1_arr = pressure_sx1
  local sy0_arr = pressure_sy0
  local sy1_arr = pressure_sy1
  local s_arr = pressure_s

  for i = 1, CELL_COUNT do
    up[i] = uv[i]
    vp[i] = vv[i]
  end

  for _ = 1, n_iters do
    for n = 1, fluid_count do
      local center = cells[n]
      local s = s_arr[center]
      if s and s ~= 0 then
        local right = right_arr[center]
        local top = top_arr[center]
        local div = uv[right] - uv[center] + vv[top] - vv[center]

        if particle_rest_density > 0 then
          local compression = pd[center] - particle_rest_density
          if compression > 0 then
            div = div - compression * STIFFNESS_COEFFICIENT
          end
        end

        local p = -(div / s) * OVER_RELAXATION
        local sx0 = sx0_arr[center]
        local sx1 = sx1_arr[center]
        local sy0 = sy0_arr[center]
        local sy1 = sy1_arr[center]
        uv[center] = uv[center] - sx0 * p
        uv[right] = uv[right] + sx1 * p
        vv[center] = vv[center] - sy0 * p
        vv[top] = vv[top] + sy1 * p
      end
    end
  end
end

local function grid_to_particles()
  local px_arr = particle_x
  local py_arr = particle_y
  local pvx_arr = particle_vx
  local pvy_arr = particle_vy
  local uv = u_vel
  local vv = v_vel
  local up = u_prev
  local vp = v_prev
  local ct = cell_type
  local cny = CELL_NUM_Y
  local h = SPACING
  local h1 = invert_spacing
  local h2 = 0.5 * h
  local x_max = CELL_NUM_X - 2
  local y_max = CELL_NUM_Y - 2

  for i = 1, NUMBER_OF_PARTICLES do
    local x = px_arr[i]
    local y = py_arr[i]

    local x0 = math_floor(x * h1)
    local y0 = math_floor((y - h2) * h1)
    if x0 < 0 then x0 = 0 elseif x0 > x_max then x0 = x_max end
    if y0 < 0 then y0 = 0 elseif y0 > y_max then y0 = y_max end
    local tx = (x - x0 * h) * h1
    local ty = ((y - h2) - y0 * h) * h1
    local sx = 1.0 - tx
    local sy = 1.0 - ty
    local d0 = sx * sy
    local d1 = tx * sy
    local d2 = tx * ty
    local d3 = sx * ty
    local nr0 = x0 * cny + y0 + 1
    local nr1 = nr0 + cny
    local nr2 = nr1 + 1
    local nr3 = nr0 + 1
    local valid0 = (ct[nr0] ~= AIR_CELL or (nr0 > cny and ct[nr0 - cny] ~= AIR_CELL)) and 1 or 0
    local valid1 = (ct[nr1] ~= AIR_CELL or (nr1 > cny and ct[nr1 - cny] ~= AIR_CELL)) and 1 or 0
    local valid2 = (ct[nr2] ~= AIR_CELL or (nr2 > cny and ct[nr2 - cny] ~= AIR_CELL)) and 1 or 0
    local valid3 = (ct[nr3] ~= AIR_CELL or (nr3 > cny and ct[nr3 - cny] ~= AIR_CELL)) and 1 or 0
    local d = valid0 * d0 + valid1 * d1 + valid2 * d2 + valid3 * d3

    if d > 0 then
      local pic_v = (
        valid0 * d0 * uv[nr0] +
        valid1 * d1 * uv[nr1] +
        valid2 * d2 * uv[nr2] +
        valid3 * d3 * uv[nr3]
      ) / d
      local corr = (
        valid0 * d0 * (uv[nr0] - up[nr0]) +
        valid1 * d1 * (uv[nr1] - up[nr1]) +
        valid2 * d2 * (uv[nr2] - up[nr2]) +
        valid3 * d3 * (uv[nr3] - up[nr3])
      ) / d
      local old_v = pvx_arr[i]
      pvx_arr[i] = (1.0 - FLIP_RATIO) * pic_v + FLIP_RATIO * (old_v + corr)
    end

    x0 = math_floor((x - h2) * h1)
    y0 = math_floor(y * h1)
    if x0 < 0 then x0 = 0 elseif x0 > x_max then x0 = x_max end
    if y0 < 0 then y0 = 0 elseif y0 > y_max then y0 = y_max end
    tx = ((x - h2) - x0 * h) * h1
    ty = (y - y0 * h) * h1
    sx = 1.0 - tx
    sy = 1.0 - ty
    d0 = sx * sy
    d1 = tx * sy
    d2 = tx * ty
    d3 = sx * ty
    nr0 = x0 * cny + y0 + 1
    nr1 = nr0 + cny
    nr2 = nr1 + 1
    nr3 = nr0 + 1
    valid0 = (ct[nr0] ~= AIR_CELL or (nr0 > 1 and ct[nr0 - 1] ~= AIR_CELL)) and 1 or 0
    valid1 = (ct[nr1] ~= AIR_CELL or (nr1 > 1 and ct[nr1 - 1] ~= AIR_CELL)) and 1 or 0
    valid2 = (ct[nr2] ~= AIR_CELL or (nr2 > 1 and ct[nr2 - 1] ~= AIR_CELL)) and 1 or 0
    valid3 = (ct[nr3] ~= AIR_CELL or (nr3 > 1 and ct[nr3 - 1] ~= AIR_CELL)) and 1 or 0
    d = valid0 * d0 + valid1 * d1 + valid2 * d2 + valid3 * d3

    if d > 0 then
      local pic_v = (
        valid0 * d0 * vv[nr0] +
        valid1 * d1 * vv[nr1] +
        valid2 * d2 * vv[nr2] +
        valid3 * d3 * vv[nr3]
      ) / d
      local corr = (
        valid0 * d0 * (vv[nr0] - vp[nr0]) +
        valid1 * d1 * (vv[nr1] - vp[nr1]) +
        valid2 * d2 * (vv[nr2] - vp[nr2]) +
        valid3 * d3 * (vv[nr3] - vp[nr3])
      ) / d
      local old_v = pvy_arr[i]
      pvy_arr[i] = (1.0 - FLIP_RATIO) * pic_v + FLIP_RATIO * (old_v + corr)
    end
  end
end

local function frame_begin()
  if not lv_canvas_frame_begin_fn or not canvas then
    return false
  end
  local ok = pcall_fn(lv_canvas_frame_begin_fn, canvas)
  return ok and true or false
end

local function frame_end(explicit_frame)
  if explicit_frame and lv_canvas_frame_end_fn then
    pcall_fn(lv_canvas_frame_end_fn, canvas)
    return
  end
  if lv_obj_invalidate_fn and canvas then
    pcall_fn(lv_obj_invalidate_fn, canvas)
  end
end

local function draw_rect(x, y, w, h, color, opa, radius)
  if rect_mode == 1 then
    rect_dsc.bg_color = color
    rect_dsc.bg_opa = opa
    rect_dsc.radius = radius or 0
    lv_canvas_draw_rect_fn(canvas, x, y, w, h, rect_dsc)
  elseif rect_mode == 2 then
    lv_canvas_draw_rect_fn(canvas, x, y, w, h, color, opa)
  end
end

local function detect_rect_mode()
  if not lv_canvas_draw_rect_fn or not canvas then
    return
  end

  rect_dsc.bg_color = C.edge
  rect_dsc.bg_opa = 1
  rect_dsc.radius = 0
  local ok = pcall_fn(lv_canvas_draw_rect_fn, canvas, 0, 0, 1, 1, rect_dsc)
  if ok then
    rect_mode = 1
    return
  end

  ok = pcall_fn(lv_canvas_draw_rect_fn, canvas, 0, 0, 1, 1, C.edge, 1)
  if ok then
    rect_mode = 2
  else
    rect_mode = 0
  end
end

local function clear_canvas()
  if lv_canvas_fill_bg_fn and canvas then
    lv_canvas_fill_bg_fn(canvas, C.bg, 255)
  end
end

local function redraw()
  if not canvas or rect_mode == 0 then
    return 0, 0, 0
  end

  local total_start_us = now_us()
  local api_us = 0
  local frame_end_us = 0
  local api_start_us = now_us()
  local explicit_frame = frame_begin()
  api_us = api_us + elapsed_us(api_start_us, now_us())

  local full_redraw = canvas_needs_full_redraw
  if full_redraw then
    canvas_needs_full_redraw = false
    api_start_us = now_us()
    clear_canvas()
    api_us = api_us + elapsed_us(api_start_us, now_us())
  end

  local edge_on_threshold = DISPLAY_ON_THRESHOLD + DISPLAY_EDGE_MARGIN
  local edge_off_threshold = DISPLAY_OFF_THRESHOLD - DISPLAY_EDGE_MARGIN
  local edge_confirm_frames = DISPLAY_EDGE_CONFIRM_FRAMES

  for i = 1, display_count do
    local cell = display_cell[i]
    local density = particle_density[cell]
    if APP.viper_ctx then
      density = (APP.viper_ctx.g:get32(CELL_COUNT * 6 + cell - 1) or 0) / FX_Q
    end
    local level = display_density[cell] * (1.0 - DISPLAY_DENSITY_BLEND) + density * DISPLAY_DENSITY_BLEND
    local prev_lit = display_lit[cell]
    local lit = prev_lit
    local edge_count = display_edge_count[cell] or 0

    display_density[cell] = level

    if level >= edge_on_threshold then
      lit = true
      edge_count = 0
    elseif level <= edge_off_threshold then
      lit = false
      edge_count = 0
    elseif level >= DISPLAY_ON_THRESHOLD then
      if prev_lit then
        edge_count = 0
      else
        if edge_count > 0 then
          edge_count = edge_count + 1
        else
          edge_count = 1
        end
        if edge_count >= edge_confirm_frames then
          lit = true
          edge_count = 0
        end
      end
    elseif level <= DISPLAY_OFF_THRESHOLD then
      if prev_lit then
        if edge_count < 0 then
          edge_count = edge_count - 1
        else
          edge_count = -1
        end
        if -edge_count >= edge_confirm_frames then
          lit = false
          edge_count = 0
        end
      else
        edge_count = 0
      end
    else
      edge_count = 0
    end
    display_lit[cell] = lit
    display_edge_count[cell] = edge_count

    if full_redraw then
      if lit then
        api_start_us = now_us()
        draw_rect(display_x[i], display_y[i], DOT_SIZE, DOT_SIZE, C.fluid, 255, 4)
        draw_rect(display_x[i] + 3, display_y[i] + 2, DOT_SIZE - 6, 2, C.fluid_core, 115, 1)
        api_us = api_us + elapsed_us(api_start_us, now_us())
      end
    elseif lit ~= prev_lit then
      api_start_us = now_us()
      if lit then
        draw_rect(display_x[i], display_y[i], DOT_SIZE, DOT_SIZE, C.fluid, 255, 4)
        draw_rect(display_x[i] + 3, display_y[i] + 2, DOT_SIZE - 6, 2, C.fluid_core, 115, 1)
      else
        draw_rect(display_x[i], display_y[i], DOT_SIZE, DOT_SIZE, C.bg, 255, 0)
      end
      api_us = api_us + elapsed_us(api_start_us, now_us())
    end
  end

  api_start_us = now_us()
  frame_end(explicit_frame)
  frame_end_us = elapsed_us(api_start_us, now_us())
  api_us = api_us + frame_end_us
  return elapsed_us(total_start_us, now_us()), api_us, frame_end_us
end

local function set_accel_from_tilt(roll, pitch)
  roll = tonumber(roll) or 0
  pitch = tonumber(pitch) or 0

  local x_scale = clamp(pitch / TILT_FULL_SCALE_DEG, -1, 1)
  local y_scale = clamp(roll / TILT_FULL_SCALE_DEG, -1, 1)

  if math_abs(x_scale) < 0.03 and math_abs(y_scale) < 0.03 then
    target_accel_x = 0
    target_accel_y = GRAVITY
    return
  end

  local pitch_rad = math_rad(clamp(pitch, -90, 90))
  local roll_rad = math_rad(clamp(roll, -180, 180))
  target_accel_x = IMU_X_SIGN * GRAVITY * math_sin(pitch_rad)
  target_accel_y = IMU_Y_SIGN * GRAVITY * math_cos(roll_rad) * math_cos(pitch_rad)
end

local function update_accel()
  accel_x = accel_x * 0.72 + target_accel_x * 0.28
  accel_y = accel_y * 0.72 + target_accel_y * 0.28
end

local function simulation_step()
  update_accel()
  if APP.viper_ctx then
    APP.viper_simulation_step(APP.viper_ctx, accel_x, accel_y)
  else
    integrate_particles(accel_x, accel_y)
    push_particles_apart(PUSH_ITER)
    particles_to_grid()
    compute_grid_forces(GRID_ITER)
    grid_to_particles()
  end
end

local function init_root()
  if lv_obj_set_style_bg_color_fn then
    pcall_fn(lv_obj_set_style_bg_color_fn, root, C.bg, MAIN_STYLE)
  end
  if lv_obj_set_style_bg_opa_fn then
    pcall_fn(lv_obj_set_style_bg_opa_fn, root, 255, MAIN_STYLE)
  end
  if lv_obj_clear_flag_fn and rawget(_G, "LV_OBJ_FLAG_SCROLLABLE") then
    pcall_fn(lv_obj_clear_flag_fn, root, rawget(_G, "LV_OBJ_FLAG_SCROLLABLE"))
  end
end

local function init_canvas()
  if CANVAS_FMT then
    canvas = lv_canvas_create_fn(root, SCREEN_W, SCREEN_H, CANVAS_FMT)
  else
    canvas = lv_canvas_create_fn(root, SCREEN_W, SCREEN_H)
  end
  if canvas and lv_obj_set_pos_fn then
    lv_obj_set_pos_fn(canvas, 0, 0)
  end
  return canvas and true or false
end

local function init_time_label()
  if not lv_label_create_fn or not lv_label_set_text_fn then
    return
  end

  time_hour_label = lv_label_create_fn(root)
  time_colon_label = lv_label_create_fn(root)
  time_minute_label = lv_label_create_fn(root)
  if not time_hour_label or not time_colon_label or not time_minute_label then
    return
  end

  local labels = { time_hour_label, time_colon_label, time_minute_label }
  for i = 1, 3 do
    local label = labels[i]
    if lv_obj_set_style_text_color_fn then
      pcall_fn(lv_obj_set_style_text_color_fn, label, C.time, MAIN_STYLE)
    end
    if lv_obj_set_style_text_font_fn and TIME_FONT then
      pcall_fn(lv_obj_set_style_text_font_fn, label, TIME_FONT, MAIN_STYLE)
    end
  end

  time_colon_visible = true
  update_time_label()
end

local function init_time_timer()
  if not runtime_tmr or not runtime_tmr.create or not time_hour_label then
    return
  end

  APP.time_timer = runtime_tmr.create()
  APP.time_timer:alarm(1000, runtime_tmr.ALARM_AUTO, function()
    if rawget(_G, "FLUID_PENDANT_APP") ~= APP then
      return
    end
    time_colon_visible = not time_colon_visible
    update_time_label()
  end)
end

local function maybe_stop_for_exit()
  if app_exiting_fn then
    local ok, exiting = pcall_fn(app_exiting_fn)
    if ok and exiting then
      APP.stop("exit")
      return true
    end
  end
  return false
end

local function tick()
  if rawget(_G, "FLUID_PENDANT_APP") ~= APP then
    return
  end
  if maybe_stop_for_exit() then
    return
  end

  simulation_step()

  local draw_total_us, draw_api_us, draw_end_us = redraw()
  profile_draw(draw_total_us, draw_api_us, draw_end_us)
end

function APP.stop(reason)
  if APP.stopped then
    return
  end

  APP.stopped = true

  if APP.timer then
    pcall_fn(function()
      APP.timer:stop()
    end)
    pcall_fn(function()
      APP.timer:unregister()
    end)
    APP.timer = nil
  end

  if APP.time_timer then
    pcall_fn(function()
      APP.time_timer:stop()
    end)
    pcall_fn(function()
      APP.time_timer:unregister()
    end)
    APP.time_timer = nil
  end

  if imu_registered and app_on_fn then
    pcall_fn(function()
      app_on_fn("imu", nil)
    end)
    imu_registered = false
  end

  if rawget(_G, "FLUID_PENDANT_APP") == APP then
    _G.FLUID_PENDANT_APP = nil
  end

end

APP.shutdown = APP.stop

if app_on_fn then
  app_on_fn("imu", function(name, roll, pitch, gx, gy, gz, ts_ms)
    if rawget(_G, "FLUID_PENDANT_APP") ~= APP then
      return
    end
    set_accel_from_tilt(roll, pitch)
  end)
  imu_registered = true
end

if APP.init_viper_engine() then
  init_display_state()
else
  init_particles()
end
build_display_lookup()
init_root()

if init_canvas() then
  detect_rect_mode()
  if APP.viper_ctx then
    APP.viper_particles_to_grid(APP.viper_ctx)
    APP.viper_ctx.cfg:set32(APP.CFG.REST_DENSITY_Q, 0)
    particle_rest_density = 0
  else
    particles_to_grid()
    particle_rest_density = 0
  end
  redraw()
  init_time_label()
  init_time_timer()

  if tmr and tmr.create then
    APP.timer = tmr.create()
    APP.timer:alarm(TICK_MS, tmr.ALARM_AUTO, function()
      local ok, err = pcall_fn(tick)
      if not ok then
        APP.stop("error")
      end
    end)
  end
end
