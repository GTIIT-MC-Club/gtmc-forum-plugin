import { apiInitializer } from "discourse/lib/api";
import GtmcOnDiscoveryRoutes from "../components/gtmc-on-discovery-routes.gjs";
import GtmcRailAnnouncements from "../components/gtmc-rail-announcements.gjs";
import GtmcRailEvents from "../components/gtmc-rail-events.gjs";
import GtmcRailNewcomer from "../components/gtmc-rail-newcomer.gjs";
import GtmcRailServers from "../components/gtmc-rail-servers.gjs";

// gtmc-right-rail 由主题提供（PLAN.md T5a），面板按这里注册的顺序从上到下排。
// gtmc_enabled 关闭时不注册，面板不渲染也不请求接口。
export default apiInitializer((api) => {
  if (!api.container.lookup("service:site-settings").gtmc_enabled) {
    return;
  }

  api.renderInOutlet(
    "gtmc-right-rail",
    <template>
      <GtmcOnDiscoveryRoutes><GtmcRailServers /></GtmcOnDiscoveryRoutes>
    </template>
  );
  api.renderInOutlet(
    "gtmc-right-rail",
    <template>
      <GtmcOnDiscoveryRoutes><GtmcRailAnnouncements /></GtmcOnDiscoveryRoutes>
    </template>
  );
  api.renderInOutlet(
    "gtmc-right-rail",
    <template>
      <GtmcOnDiscoveryRoutes><GtmcRailNewcomer /></GtmcOnDiscoveryRoutes>
    </template>
  );
  api.renderInOutlet(
    "gtmc-right-rail",
    <template>
      <GtmcOnDiscoveryRoutes><GtmcRailEvents /></GtmcOnDiscoveryRoutes>
    </template>
  );
});
