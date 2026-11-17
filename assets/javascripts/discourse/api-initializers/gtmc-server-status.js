import { apiInitializer } from "discourse/lib/api";
import GtmcServerStatus from "../components/gtmc-server-status.gjs";

// discovery-above 在话题列表和导航栏之间，category、tag 作为出口参数传入（见组件的 shouldRender）。
export default apiInitializer((api) => {
  api.renderInOutlet("discovery-above", GtmcServerStatus);
});
