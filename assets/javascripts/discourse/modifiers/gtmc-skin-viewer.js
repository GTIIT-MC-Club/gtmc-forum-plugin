import { registerDestructor } from "@ember/destroyable";
import Modifier from "ember-modifier";
import loadScript from "discourse/lib/load-script";

// 文件名带版本：升级时换名，浏览器不会拿到旧缓存
const SCRIPT_URL =
  "/plugins/discourse-gtmc/javascripts/skinview3d-3.4.2.bundle.js";

// 高度与 gtmc-rail.scss 的 .gtmc-rail-characters__stage 一致
const WIDTH = 220;
const HEIGHT = 260;

/**
 * 在 canvas 上用 skinview3d 画一个可拖动旋转的角色。skinUrl 变了只换贴图，不重建 WebGL 上下文。
 * 脚本、WebGL 或贴图加载失败时调用 onError。
 */
export default class GtmcSkinViewer extends Modifier {
  #canvas = null;
  #viewer = null;
  #observer = null;
  #wanted = null;
  #isApplying = false;
  #isDisposed = false;

  constructor(owner, args) {
    super(owner, args);
    registerDestructor(this, (instance) => instance.#dispose());
  }

  modify(canvas, _positional, { skinUrl, isSlim, onError }) {
    this.#canvas = canvas;
    this.#wanted = { skinUrl, isSlim };
    this.#apply(onError);
  }

  // 一次只换一张：连点几个角色时，先点的贴图晚到也不会盖掉后点的
  async #apply(onError) {
    if (this.#isApplying) {
      return;
    }
    this.#isApplying = true;
    try {
      if (!this.#viewer) {
        await loadScript(SCRIPT_URL);
        if (this.#isDisposed) {
          return;
        }
        this.#createViewer();
      }
      let applied = null;
      while (!this.#isDisposed && applied !== this.#wanted) {
        applied = this.#wanted;
        await this.#viewer.loadSkin(applied.skinUrl, {
          model: applied.isSlim ? "slim" : "default",
        });
      }
    } catch {
      if (!this.#isDisposed) {
        onError();
      }
    } finally {
      this.#isApplying = false;
    }
  }

  #createViewer() {
    const { SkinViewer, WalkingAnimation } = window.skinview3d;
    this.#viewer = new SkinViewer({
      canvas: this.#canvas,
      width: WIDTH,
      height: HEIGHT,
      zoom: 0.85,
    });
    // 滚轮留给页面滚动，只许拖动旋转
    this.#viewer.controls.enableZoom = false;
    this.#viewer.controls.enablePan = false;
    this.#canvas.style.touchAction = "pan-y";

    if (!window.matchMedia("(prefers-reduced-motion: reduce)").matches) {
      this.#viewer.autoRotate = true;
      this.#viewer.autoRotateSpeed = 0.5;
      this.#viewer.animation = new WalkingAnimation();
      this.#viewer.animation.speed = 0.5;
    }

    // 滚出屏幕时不画
    this.#observer = new IntersectionObserver(([entry]) => {
      this.#viewer.renderPaused = !entry.isIntersecting;
    });
    this.#observer.observe(this.#canvas);
  }

  #dispose() {
    this.#isDisposed = true;
    this.#observer?.disconnect();
    this.#viewer?.dispose();
    // dispose 不释放 WebGL 上下文，浏览器同时只许十几个；每次换页都会新建，所以立刻还掉
    this.#viewer?.renderer.forceContextLoss();
    this.#viewer = null;
  }
}
