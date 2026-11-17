import { apiInitializer } from "discourse/lib/api";
import GtmcMobileNewcomer from "../components/gtmc-mobile-newcomer.gjs";
import GtmcMobileStatusStrip from "../components/gtmc-mobile-status-strip.gjs";

// 手机上没有右栏：服务器状态条和新人进度卡放在首页话题列表上方（discovery-above 在列表和导航栏之间）。
// 两个组件在桌面宽度下都被样式隐藏，不需要在这里判断屏幕大小。
export default apiInitializer((api) => {
  api.renderInOutlet("discovery-above", GtmcMobileStatusStrip);
  api.renderInOutlet("discovery-above", GtmcMobileNewcomer);
});
