import {
  composePose,
  shortestAngleError,
  verifyHandReturn,
} from "./motion-core.js";

const canvas = document.querySelector("#face");
const context = canvas.getContext("2d");
const status = document.querySelector("#status");
const testLabel = document.querySelector("#test-result");

const state = {
  theme: "cel",
  sleep: false,
  lowBattery: false,
  charging: false,
  idleStartedAt: Number.NEGATIVE_INFINITY,
  tapStartedAt: Number.NEGATIVE_INFINITY,
  idleBucket: -1,
  previewTimestamp: null,
};

const paths = {
  celBody: "./assets/season1-body-normal.png?v=arm-hands-1",
  celHour: "./assets/season1-hour-arm.png?v=arm-hands-1",
  celMinute: "./assets/season1-minute-arm.png?v=arm-hands-1",
  toonBody: "./assets/season1-3d-body.png?v=arm-hands-1",
  toonArm: "./assets/season1-3d-arm.png?v=arm-hands-1",
};

// One shared analog hub on the chest. These are Patrick's arms used as
// clock hands — thick star limbs rotating around the same center.
const CLOCK_RIG = Object.freeze({
  hub: Object.freeze({ x: 360, y: 498 }),
  hourLength: 250,
  minuteLength: 340,
});

function loadImage(src) {
  return new Promise((resolve, reject) => {
    const image = new Image();
    image.onload = () => resolve(image);
    image.onerror = () => reject(new Error(`Unable to load ${src}`));
    image.src = src;
  });
}

const assets = Object.fromEntries(
  await Promise.all(
    Object.entries(paths).map(async ([key, path]) => [key, await loadImage(path)]),
  ),
);

function pad(value) {
  return String(value).padStart(2, "0");
}

function drawTicks(ctx, dimmed) {
  const marks = [
    [360, 27, 360, 43],
    [532, 52, 526, 64],
    [665, 208, 653, 214],
    [693, 440, 677, 440],
    [665, 672, 653, 666],
    [532, 828, 526, 816],
    [360, 853, 360, 837],
    [188, 828, 194, 816],
    [55, 672, 67, 666],
    [27, 440, 43, 440],
    [55, 208, 67, 214],
    [188, 52, 194, 64],
  ];

  marks.forEach(([x1, y1, x2, y2], index) => {
    const major = index % 3 === 0;
    ctx.beginPath();
    ctx.moveTo(x1, y1);
    ctx.lineTo(x2, y2);
    ctx.strokeStyle = `rgba(255,255,255,${dimmed ? 0.18 : major ? 0.72 : 0.3})`;
    ctx.lineWidth = major ? 5 : 3;
    ctx.lineCap = "round";
    ctx.stroke();
  });
}

function drawInformation(ctx, date, sleeping) {
  ctx.textAlign = "center";
  ctx.textBaseline = "middle";
  ctx.fillStyle = sleeping ? "#bba8ca" : "#f4f0f2";
  ctx.font = '300 68px "Segoe UI","PingFang TC",sans-serif';
  ctx.fillText(`${pad(date.getHours())}:${pad(date.getMinutes())}`, 360, 83);

  ctx.textAlign = "left";
  ctx.fillStyle = "rgba(255,255,255,.48)";
  ctx.font = '500 23px "Segoe UI","PingFang TC",sans-serif';
  const weekdays = ["日", "一", "二", "三", "四", "五", "六"];
  ctx.fillText(`週${weekdays[date.getDay()]} ${date.getDate()}`, 54, 132);

  ctx.textAlign = "right";
  ctx.fillText(state.theme === "cel" ? "1999 CEL" : "TOON 3D", 666, 132);
}

function drawCroppedArm(
  ctx,
  image,
  angleDegrees,
  length,
  pivotX,
  pivotY,
  widthScale,
) {
  // widthScale is the on-screen width/length ratio for the pointer.
  const width = length * widthScale;
  ctx.save();
  ctx.translate(pivotX, pivotY);
  ctx.rotate((angleDegrees * Math.PI) / 180);
  ctx.drawImage(image, -width / 2, -length, width, length);
  ctx.restore();
}

function drawClockHub(ctx, theme) {
  ctx.save();
  ctx.beginPath();
  ctx.arc(CLOCK_RIG.hub.x, CLOCK_RIG.hub.y, 9, 0, Math.PI * 2);
  if (theme === "cel") {
    ctx.fillStyle = "#f87870";
  } else {
    const fill = ctx.createRadialGradient(
      CLOCK_RIG.hub.x - 2,
      CLOCK_RIG.hub.y - 2,
      1,
      CLOCK_RIG.hub.x,
      CLOCK_RIG.hub.y,
      10,
    );
    fill.addColorStop(0, "#ff9a8c");
    fill.addColorStop(1, "#d95d55");
    ctx.fillStyle = fill;
  }
  ctx.fill();
  ctx.strokeStyle = theme === "cel" ? "#55292f" : "rgba(76,37,37,.68)";
  ctx.lineWidth = 2.5;
  ctx.stroke();
  ctx.restore();
}

function applyRigTransform(ctx, pose) {
  const y = pose.tap.y + pose.slump * 15;
  const scale = pose.tap.scale;
  ctx.translate(360, 490);
  ctx.rotate((pose.slump * 4.5 * Math.PI) / 180);
  ctx.scale(scale, scale);
  ctx.translate(-360, -490 + y);
}

function drawCel(ctx, pose) {
  const bodyHeight = 665;
  const bodyWidth = bodyHeight * (assets.celBody.width / assets.celBody.height);
  const bodyTop = 165;
  const pivotY = bodyTop + bodyHeight * 0.47;
  const breathScale = 1 + pose.breathing * 0.004;

  ctx.save();
  applyRigTransform(ctx, pose);
  ctx.translate(360, pivotY);
  ctx.scale(breathScale, 1);
  ctx.translate(-360, -pivotY);

  const bodyX = 360 - bodyWidth / 2;
  ctx.drawImage(assets.celBody, bodyX, bodyTop, bodyWidth, bodyHeight);
  drawCroppedArm(
    ctx,
    assets.celMinute,
    pose.hands.minute,
    CLOCK_RIG.minuteLength,
    CLOCK_RIG.hub.x,
    CLOCK_RIG.hub.y,
    0.36,
  );
  drawCroppedArm(
    ctx,
    assets.celHour,
    pose.hands.hour,
    CLOCK_RIG.hourLength,
    CLOCK_RIG.hub.x,
    CLOCK_RIG.hub.y,
    0.44,
  );
  drawClockHub(ctx, "cel");
  ctx.restore();
}

function drawToon3D(ctx, pose) {
  const bodyHeight = 665;
  const bodyWidth = bodyHeight * (assets.toonBody.width / assets.toonBody.height);
  const bodyTop = 165;
  const pivotY = bodyTop + bodyHeight * 0.48;
  const bodyScale = 1 + pose.breathing * 0.0035;

  ctx.save();
  applyRigTransform(ctx, pose);
  ctx.translate(360, pivotY);
  ctx.scale(bodyScale, 1);
  ctx.translate(-360, -pivotY);

  const bodyX = 360 - bodyWidth / 2;
  ctx.drawImage(assets.toonBody, bodyX, bodyTop, bodyWidth, bodyHeight);
  drawCroppedArm(
    ctx,
    assets.toonArm,
    pose.hands.minute,
    CLOCK_RIG.minuteLength,
    CLOCK_RIG.hub.x,
    CLOCK_RIG.hub.y,
    0.34,
  );
  drawCroppedArm(
    ctx,
    assets.toonArm,
    pose.hands.hour,
    CLOCK_RIG.hourLength,
    CLOCK_RIG.hub.x,
    CLOCK_RIG.hub.y,
    0.42,
  );
  drawClockHub(ctx, "toon3d");
  ctx.restore();
}

function drawStateEffects(ctx, pose, nowSeconds) {
  if (pose.charging) {
    const alpha = 0.06 + pose.chargingPulse * 0.12;
    const glow = ctx.createLinearGradient(0, 180, 0, 820);
    glow.addColorStop(0, `rgba(91,255,179,0)`);
    glow.addColorStop(0.55, `rgba(91,255,179,${alpha})`);
    glow.addColorStop(1, `rgba(91,255,179,0)`);
    ctx.fillStyle = glow;
    ctx.fillRect(140, 170, 440, 650);
  }

  if (pose.sleep) {
    const phase = (nowSeconds % 3.2) / 3.2;
    ctx.globalAlpha = Math.sin(phase * Math.PI) * 0.7;
    ctx.fillStyle = "#bda8d4";
    ctx.font = `600 ${26 + phase * 18}px "Segoe UI",sans-serif`;
    ctx.textAlign = "left";
    ctx.fillText("Z", 510 + phase * 50, 310 - phase * 75);
    ctx.globalAlpha = 1;
  }
}

function updateStatus(pose) {
  const stateName = pose.sleep
    ? "睡眠"
    : pose.lowBattery
      ? "低電量"
      : pose.charging
        ? "充電"
        : "清醒";
  const moving = pose.idleWeight > 0.001 || pose.tap.weight > 0.001;
  status.textContent = `${state.theme === "cel" ? "第一季 2D" : "第一季 Toon 3D"} · ${stateName} · ${
    moving ? "動作中" : "雙臂準確報時"
  }`;
}

function render() {
  const date = state.previewTimestamp === null
    ? new Date()
    : new Date(state.previewTimestamp);
  const nowSeconds = date.getTime() / 1000;
  const bucket = Math.floor(nowSeconds / 12);
  if (bucket !== state.idleBucket) {
    state.idleBucket = bucket;
    state.idleStartedAt = nowSeconds;
  }

  const pose = composePose({
    date,
    nowSeconds,
    idleStartedAt: state.previewTimestamp === null
      ? state.idleStartedAt
      : Number.NEGATIVE_INFINITY,
    tapStartedAt: state.previewTimestamp === null
      ? state.tapStartedAt
      : Number.NEGATIVE_INFINITY,
    sleep: state.sleep,
    lowBattery: state.lowBattery,
    charging: state.charging,
  });

  context.clearRect(0, 0, canvas.width, canvas.height);
  context.fillStyle = "#000";
  context.fillRect(0, 0, canvas.width, canvas.height);
  drawStateEffects(context, pose, nowSeconds);
  drawTicks(context, pose.sleep);
  drawInformation(context, date, pose.sleep);

  if (state.theme === "cel") drawCel(context, pose);
  else drawToon3D(context, pose);

  const hourError = shortestAngleError(pose.hands.hour, pose.base.hour);
  const minuteError = shortestAngleError(pose.hands.minute, pose.base.minute);
  window.__patrickFace = {
    theme: state.theme,
    state: { ...state },
    pose,
    hourError,
    minuteError,
    exactTime: hourError === 0 && minuteError === 0,
    rig: {
      hub: { ...CLOCK_RIG.hub },
      hourBase: { ...CLOCK_RIG.hub },
      minuteBase: { ...CLOCK_RIG.hub },
      hourLength: CLOCK_RIG.hourLength,
      minuteLength: CLOCK_RIG.minuteLength,
    },
  };
  updateStatus(pose);
  requestAnimationFrame(render);
}

function setToggle(id, key) {
  document.querySelector(id).addEventListener("click", (event) => {
    state[key] = !state[key];
    event.currentTarget.classList.toggle("active", state[key]);
  });
}

document.querySelector("#theme-cel").addEventListener("click", () => {
  state.theme = "cel";
  document.querySelector("#theme-cel").classList.add("active");
  document.querySelector("#theme-toon3d").classList.remove("active");
});

document.querySelector("#theme-toon3d").addEventListener("click", () => {
  state.theme = "toon3d";
  document.querySelector("#theme-toon3d").classList.add("active");
  document.querySelector("#theme-cel").classList.remove("active");
});

document.querySelector("#gesture").addEventListener("click", () => {
  state.idleStartedAt = Date.now() / 1000;
});

canvas.addEventListener("pointerdown", () => {
  state.tapStartedAt = Date.now() / 1000;
  navigator.vibrate?.(20);
});

setToggle("#sleep", "sleep");

document.querySelector("#low-battery").addEventListener("click", (event) => {
  state.lowBattery = !state.lowBattery;
  if (state.lowBattery) state.charging = false;
  event.currentTarget.classList.toggle("active", state.lowBattery);
  document.querySelector("#charging").classList.toggle("active", state.charging);
});

document.querySelector("#charging").addEventListener("click", (event) => {
  state.charging = !state.charging;
  if (state.charging) state.lowBattery = false;
  event.currentTarget.classList.toggle("active", state.charging);
  document.querySelector("#low-battery").classList.toggle("active", state.lowBattery);
});

document.querySelector("#return-test").addEventListener("click", () => {
  const startedAt = Date.now() / 1000;
  state.idleStartedAt = startedAt;
  testLabel.textContent = "TESTING…";
  testLabel.style.color = "#d9bd72";
  setTimeout(() => {
    const nowSeconds = Date.now() / 1000;
    const result = verifyHandReturn({
      date: new Date(),
      nowSeconds,
      idleStartedAt: startedAt,
    });
    testLabel.textContent = result.pass
      ? "PASS · HANDS RETURNED EXACTLY"
      : `FAIL · H ${result.hourError.toFixed(6)} M ${result.minuteError.toFixed(6)}`;
    testLabel.style.color = result.pass ? "#7dca9c" : "#ef8080";
  }, 1900);
});

window.__setPatrickPreviewTime = (hours, minutes, seconds = 0) => {
  const date = new Date();
  date.setHours(hours, minutes, seconds, 0);
  state.previewTimestamp = date.getTime();
};

window.__clearPatrickPreviewTime = () => {
  state.previewTimestamp = null;
};

render();
