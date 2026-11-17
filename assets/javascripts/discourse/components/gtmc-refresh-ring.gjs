import { array, concat } from "@ember/helper";
import { trustHTML } from "@ember/template";
import { i18n } from "discourse-i18n";

// 周期是接口给的数字，已在 gtmc-server-status-response.js 里确认是正整数，才可以写进 style。
// 每次刷新 @refreshCount 加一，each 的 key 变了整个圆环重建，动画从头转一圈。
<template>
  <span
    class="gtmc-refresh-ring"
    data-tooltip={{i18n
      "gtmc.servers.refresh_tooltip"
      seconds=@refreshIntervalSeconds
    }}
  >
    {{#each (array @refreshCount) key="@identity"}}
      <svg
        aria-hidden="true"
        class="gtmc-refresh-ring__svg"
        style={{trustHTML
          (concat "--gtmc-refresh-seconds:" @refreshIntervalSeconds "s")
        }}
        viewBox="0 0 16 16"
      >
        <circle class="gtmc-refresh-ring__track" cx="8" cy="8" r="6" />
        <circle class="gtmc-refresh-ring__elapsed" cx="8" cy="8" r="6" />
      </svg>
    {{/each}}
  </span>
</template>
