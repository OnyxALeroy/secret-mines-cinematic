precision highp float;

uniform float iTime;
uniform vec3 iResolution;

// --- CONFIGURATION ---
#define MAX_STEPS 140
#define MAX_DIST 140.0
#define SURF_DIST 0.001

// Dimensions - GRAND SCALE
const float MAP_SCALE = 18.0;
const float ROOM_RADIUS = 12.0;
const float CORRIDOR_WIDTH = 6.0;
const float WALL_HEIGHT = 7.0;
const float ARCH_WIDTH = 4.5;

// --- UTILS & NOISE ---

float hash21(vec2 p) {
    p = fract(p * vec2(234.34, 435.345));
    p += dot(p, p + 34.23);
    return fract(p.x * p.y);
}

vec2 hash22(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * vec3(.1031, .1030, .0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.xx + p3.yz) * p3.zy);
}

// --- VORONOI FLOOR LOGIC ---
vec3 voronoi(vec2 uv) {
    vec2 n = floor(uv);
    vec2 f = fract(uv);

    vec2 mg, mr;
    float md = 8.0;

    for (int j = -1; j <= 1; j++) {
        for (int i = -1; i <= 1; i++) {
            vec2 g = vec2(float(i), float(j));
            vec2 o = hash22(n + g);
            vec2 r = g + o - f;
            float d = dot(r, r);
            if (d < md) {
                md = d;
                mr = r;
                mg = g;
            }
        }
    }

    md = 8.0;
    for (int j = -2; j <= 2; j++) {
        for (int i = -2; i <= 2; i++) {
            vec2 g = mg + vec2(float(i), float(j));
            vec2 o = hash22(n + g);
            vec2 r = g + o - f;

            if (dot(mr - r, mr - r) > 0.00001) {
                float d = dot(0.5 * (mr + r), normalize(r - mr));
                md = min(md, d);
            }
        }
    }
    return vec3(md, n + mg);
}

// --- SDF PRIMITIVES ---

float sdBox(vec3 p, vec3 b) {
    vec3 q = abs(p) - b;
    return length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
}

float sdBox2D(vec2 p, vec2 b) {
    vec2 d = abs(p) - b;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
}

float opUnion(float d1, float d2) {
    return min(d1, d2);
}
float opSubtract(float d1, float d2) {
    return max(-d1, d2);
}

// --- ARCHITECTURE ---

float sdSimpleArch2D(vec2 p, float w) {
    p.x = abs(p.x);
    float straightH = WALL_HEIGHT * 0.5;
    float dBox = p.x - w;
    float dCircle = length(vec2(p.x, p.y - straightH)) - w;
    float d = (p.y < straightH) ? dBox : dCircle;
    return max(d, -p.y);
}

float GetArchDistance(vec3 p) {
    vec3 pSym = abs(p);
    float archPos = MAP_SCALE - ROOM_RADIUS + 1.0;
    float archThick = 0.8;

    vec3 pArchZ = pSym - vec3(MAP_SCALE, 0.0, archPos);
    float wallZ = sdBox(pArchZ - vec3(0, WALL_HEIGHT / 2.0, 0), vec3(CORRIDOR_WIDTH / 2.0 + 2.0, WALL_HEIGHT / 2.0, archThick));
    float holeZ = sdSimpleArch2D(pArchZ.xy, ARCH_WIDTH * 0.5);
    float archZ = opSubtract(holeZ, wallZ);

    vec3 pArchX = pSym - vec3(archPos, 0.0, MAP_SCALE);
    float wallX = sdBox(pArchX - vec3(0, WALL_HEIGHT / 2.0, 0), vec3(archThick, WALL_HEIGHT / 2.0, CORRIDOR_WIDTH / 2.0 + 2.0));
    float holeX = sdSimpleArch2D(pArchX.zy, ARCH_WIDTH * 0.5);
    float archX = opSubtract(holeX, wallX);

    return opUnion(archZ, archX);
}

float GetMapDistance(vec3 p) {
    float dVertical = min(p.y, WALL_HEIGHT - p.y);
    vec2 p2 = p.xz;
    vec2 pSym = abs(p2);
    float dRoom = length(pSym - vec2(MAP_SCALE)) - ROOM_RADIUS;
    float dCorZ = sdBox2D(pSym - vec2(MAP_SCALE, 0.0), vec2(CORRIDOR_WIDTH * 0.5, MAP_SCALE + 2.0));
    float dCorX = sdBox2D(pSym - vec2(0.0, MAP_SCALE), vec2(MAP_SCALE + 2.0, CORRIDOR_WIDTH * 0.5));
    float dAir = opUnion(dRoom, opUnion(dCorZ, dCorX));
    float dWalls = -dAir;
    float dArches = GetArchDistance(p);
    return min(dArches, min(dVertical, dWalls));
}

// --- PROCEDURAL TEXTURES (RESCALED) ---

vec3 getFloorTexture(vec3 p) {
    // INCREASED SCALE: 0.5 -> 1.5
    // Stones are now 3x smaller than before
    vec3 v = voronoi(p.xz * 1.5);

    float distToEdge = v.x;
    vec2 cellID = v.yz;

    // Adjusted smoothness for tighter mortar lines
    float mortarMask = smoothstep(0.02, 0.06, distToEdge);

    float idHash = hash21(cellID);
    vec3 stoneColor = vec3(0.3, 0.28, 0.26);
    stoneColor += (idHash - 0.5) * 0.15;

    // Increased grain frequency
    float grain = hash21(p.xz * 20.0);
    stoneColor *= 0.9 + 0.2 * grain;

    vec3 mortarColor = vec3(0.12);

    return mix(mortarColor, stoneColor, mortarMask);
}

vec3 getWallTexture(vec3 p, vec3 n) {
    vec2 uv;
    if (abs(n.x) > 0.5) uv = p.zy; else uv = p.xy;

    // INCREASED SCALE: Was (0.8, 1.2), now (2.5, 2.0)
    // Bricks are much smaller and denser
    uv *= vec2(2.5, 2.0);

    float rowOffset = mod(floor(uv.y), 2.0) * 0.5;
    uv.x += rowOffset;

    vec2 tileId = floor(uv);
    vec2 localUv = fract(uv);

    vec2 mortarSmooth = smoothstep(0.0, 0.08, localUv) * (1.0 - smoothstep(0.92, 1.0, localUv));
    float mortarFactor = mortarSmooth.x * mortarSmooth.y;

    float rand = hash21(tileId);
    vec3 brickBase = vec3(0.6, 0.55, 0.5);
    vec3 brickVariation = brickBase + (rand - 0.5) * 0.25;

    float grit = hash21(uv * 15.0) * 0.1;
    brickVariation -= grit;

    return mix(vec3(0.15), brickVariation, mortarFactor);
}

// --- RENDERING ---

vec3 GetNormal(vec3 p) {
    float d = GetMapDistance(p);
    vec2 e = vec2(0.001, 0);
    vec3 n = d - vec3(
                GetMapDistance(p - e.xyy),
                GetMapDistance(p - e.yxy),
                GetMapDistance(p - e.yyx)
            );
    return normalize(n);
}

float RayMarch(vec3 ro, vec3 rd) {
    float dO = 0.0;
    for (int i = 0; i < MAX_STEPS; i++) {
        vec3 p = ro + rd * dO;
        float dS = GetMapDistance(p);
        dO += dS;
        if (dO > MAX_DIST || abs(dS) < SURF_DIST) break;
    }
    return dO;
}

vec3 GetMaterialColor(vec3 p, vec3 n) {
    vec3 col = vec3(0.0);
    float upDot = dot(n, vec3(0, 1, 0));

    if (upDot > 0.99) {
        col = getFloorTexture(p);
    } else if (upDot < -0.99) {
        col = vec3(0.8) - hash21(p.xz * 5.0) * 0.1;
    } else {
        vec3 stoneTex = getWallTexture(p, n);
        float distToRoomCenter = length(abs(p.xz) - vec2(MAP_SCALE, MAP_SCALE));
        float archDist = abs(distToRoomCenter - ROOM_RADIUS);

        if (archDist < 2.0 && p.y < WALL_HEIGHT - 0.1) {
            col = stoneTex * 0.6;
        } else {
            if (distToRoomCenter < ROOM_RADIUS - 1.0) {
                col = stoneTex * vec3(1.1, 0.6, 0.6);
            } else {
                col = stoneTex * vec3(1.0, 0.98, 0.95);
            }
        }
    }
    return col;
}

void GetCameraPath(float t, out vec3 pos, out vec3 target) {
    float pathRadius = MAP_SCALE;
    float turnRadius = 10.0;
    float straightLen = (2.0 * pathRadius) - (2.0 * turnRadius);
    float arcLen = 1.570796 * turnRadius;
    float segmentLen = straightLen + arcLen;
    float totalLoopLen = 4.0 * segmentLen;
    float d = mod(t * 4.5, totalLoopLen);
    float sideIdx = floor(d / segmentLen);
    float localD = mod(d, segmentLen);
    vec3 segOrigin, segDir, arcCenter;
    float startAngle;
    if (sideIdx < 0.5) {
        segOrigin = vec3(-pathRadius + turnRadius, 0, -pathRadius);
        segDir = vec3(1, 0, 0);
        arcCenter = vec3(pathRadius - turnRadius, 0, -pathRadius + turnRadius);
        startAngle = -1.5708;
    } else if (sideIdx < 1.5) {
        segOrigin = vec3(pathRadius, 0, -pathRadius + turnRadius);
        segDir = vec3(0, 0, 1);
        arcCenter = vec3(pathRadius - turnRadius, 0, pathRadius - turnRadius);
        startAngle = 0.0;
    } else if (sideIdx < 2.5) {
        segOrigin = vec3(pathRadius - turnRadius, 0, pathRadius);
        segDir = vec3(-1, 0, 0);
        arcCenter = vec3(-pathRadius + turnRadius, 0, pathRadius - turnRadius);
        startAngle = 1.5708;
    } else {
        segOrigin = vec3(-pathRadius, 0, pathRadius - turnRadius);
        segDir = vec3(0, 0, -1);
        arcCenter = vec3(-pathRadius + turnRadius, 0, -pathRadius + turnRadius);
        startAngle = 3.14159;
    }
    if (localD < straightLen) {
        pos = segOrigin + segDir * localD;
    } else {
        float angleOffset = (localD - straightLen) / turnRadius;
        float currentAngle = startAngle + angleOffset;
        pos = arcCenter + vec3(cos(currentAngle), 0, sin(currentAngle)) * turnRadius;
    }
    pos.y = 1.4;
    float lookAhead = 2.0;
    float nextD = d + lookAhead;
    float n_sideIdx = floor(mod(nextD, totalLoopLen) / segmentLen);
    float n_localD = mod(nextD, segmentLen);
    vec3 n_segOrigin, n_segDir, n_arcCenter;
    float n_startAngle;
    if (n_sideIdx < 0.5) {
        n_segOrigin = vec3(-pathRadius + turnRadius, 0, -pathRadius);
        n_segDir = vec3(1, 0, 0);
        n_arcCenter = vec3(pathRadius - turnRadius, 0, -pathRadius + turnRadius);
        n_startAngle = -1.5708;
    } else if (n_sideIdx < 1.5) {
        n_segOrigin = vec3(pathRadius, 0, -pathRadius + turnRadius);
        n_segDir = vec3(0, 0, 1);
        n_arcCenter = vec3(pathRadius - turnRadius, 0, pathRadius - turnRadius);
        n_startAngle = 0.0;
    } else if (n_sideIdx < 2.5) {
        n_segOrigin = vec3(pathRadius - turnRadius, 0, pathRadius);
        n_segDir = vec3(-1, 0, 0);
        n_arcCenter = vec3(-pathRadius + turnRadius, 0, pathRadius - turnRadius);
        n_startAngle = 1.5708;
    } else {
        n_segOrigin = vec3(-pathRadius, 0, pathRadius - turnRadius);
        n_segDir = vec3(0, 0, -1);
        n_arcCenter = vec3(-pathRadius + turnRadius, 0, -pathRadius + turnRadius);
        n_startAngle = 3.14159;
    }
    if (n_localD < straightLen) {
        target = n_segOrigin + n_segDir * n_localD;
    } else {
        float n_angleOffset = (n_localD - straightLen) / turnRadius;
        float n_currentAngle = n_startAngle + n_angleOffset;
        target = n_arcCenter + vec3(cos(n_currentAngle), 0, sin(n_currentAngle)) * turnRadius;
    }
    target.y = 1.4;
}

void main() {
    vec2 uv = (gl_FragCoord.xy - 0.5 * iResolution.xy) / iResolution.y;

    vec3 ro, target;
    GetCameraPath(iTime, ro, target);

    vec3 fwd = normalize(target - ro);
    vec3 right = normalize(cross(vec3(0, 1, 0), fwd));
    vec3 up = cross(fwd, right);

    vec3 rd = normalize(fwd + right * uv.x + up * uv.y);

    float d = RayMarch(ro, rd);

    vec3 col = vec3(0.0);

    if (d < MAX_DIST) {
        vec3 p = ro + rd * d;
        vec3 n = GetNormal(p);
        vec3 albedo = GetMaterialColor(p, n);

        vec3 lightPos = ro + vec3(0, 2.0, 0);
        vec3 l = normalize(lightPos - p);
        float dif = clamp(dot(n, l), 0.0, 1.0);
        vec3 ref = reflect(-l, n);
        float spec = pow(max(dot(ref, -rd), 0.0), 16.0) * 0.2;
        float att = 1.0 / (1.0 + d * d * 0.003);

        col = (albedo * dif + spec) * att;
        col += albedo * 0.05;
        col = mix(col, vec3(0.02, 0.02, 0.05), 1.0 - exp(-d * 0.015));
    }
    col = pow(col, vec3(0.4545));
    gl_FragColor = vec4(col, 1.0);
}
